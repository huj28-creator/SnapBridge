#!/usr/bin/env python3
"""Unattended profile-only renewal for a pinned SnapBridge installation.

Installed locally by setup_renewal.py. No password handling, app deletion,
device unlocking, certificate revocation, or change to the app's behavior.
"""
from pathlib import Path
from datetime import datetime, timedelta, timezone
import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

UTC = timezone.utc
DEFAULT_HOME = Path.home() / "Library/Application Support/SnapBridge Renewal"


def now():
    return datetime.now(UTC)


def stamp(value):
    return value.astimezone(UTC).isoformat()


def date(value):
    parsed = datetime.fromisoformat(value)
    return parsed.replace(tzinfo=UTC) if parsed.tzinfo is None else parsed.astimezone(UTC)


def read_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else (default or {})


def save_json(path, data):
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(data, indent=2) + "\n")
    temp.chmod(0o600)
    temp.replace(path)


class RenewalError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message
        super().__init__(message)


def run(command, timeout=60, log=None):
    """Bound subprocesses and their children; never leave a stuck build running."""
    with tempfile.TemporaryFile() as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise RenewalError("deferred", "A device or signing command timed out; retry later.")
        output.seek(0)
        result = output.read().decode(errors="replace")
    if log is not None:
        # Bounded diagnostic output, stored only in the user's private directory.
        log.write_text(result[-300000:])
    return code, result


def profile(app):
    code, content = run(["/usr/bin/security", "cms", "-D", "-i",
                         str(app if app.suffix == ".mobileprovision" else app / "embedded.mobileprovision")])
    if code:
        raise RenewalError("error", "Cannot read the signed app's provisioning profile.")
    return plistlib.loads(content.encode())


def validate_app(app, config, minimum_expiry):
    is_profile = app.suffix == ".mobileprovision"
    info = dict(CFBundleIdentifier=config["bundle_id"], CFBundleVersion=config["build_version"]) if is_profile else plistlib.loads((app / "Info.plist").read_bytes())
    p = profile(app)
    expected = config["team"] + "." + config["bundle_id"]
    if info.get("CFBundleIdentifier") != config["bundle_id"]:
        raise RenewalError("error", "Refusing a different app identity.")
    if str(info.get("CFBundleVersion")) != str(config["build_version"]):
        raise RenewalError("app_changed", "The signed build differs from the pinned installation.")
    if p.get("Entitlements", {}).get("application-identifier") != expected:
        raise RenewalError("error", "Refusing a different signing team or keychain identity.")
    if config["device_udid"] not in p.get("ProvisionedDevices", []):
        raise RenewalError("error", "The profile does not include the configured iPhone.")
    anchors = set(config.get("installed_certificate_sha256", []))
    certificates = {hashlib.sha256(c).hexdigest() for c in p.get("DeveloperCertificates", [])}
    if not anchors or not anchors.intersection(certificates):
        raise RenewalError("certificate_changed", "The profile does not contain the installed app's signing certificate.")
    if p.get("Entitlements") != config.get("expected_profile_entitlements"):
        raise RenewalError("app_changed", "The renewed profile changes the app's permitted capabilities.")
    expiry = p["ExpirationDate"].replace(tzinfo=UTC)
    if expiry < minimum_expiry:
        raise RenewalError("profile_not_extended", "Apple has not issued a sufficiently fresh profile yet.")
    if not is_profile:
        code, _ = run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
        if code:
            raise RenewalError("error", "The app signature did not verify; installation skipped.")
    return p, info


def device_arguments(config, transport="network"):
    args = ["-u", config["device_udid"]]
    return args + (["-n"] if transport == "network" else [])


def devicectl_json(command, timeout=30, log=None):
    code, output = run(["/usr/bin/xcrun", "devicectl", "--json-output", "-", *command],
                       timeout=timeout, log=log)
    start = output.find('{\n  "')
    if start < 0:
        raise RenewalError("deferred", "Apple's wireless device service returned no structured response.")
    try:
        result = json.loads(output[start:])
    except json.JSONDecodeError:
        raise RenewalError("deferred", "Apple's wireless device service returned an invalid response.")
    if code or result.get("info", {}).get("outcome") == "failed" or result.get("error"):
        raise RenewalError("deferred", "Apple's trusted Wi-Fi device service is temporarily unavailable.")
    return result.get("result", {})


def installed_app_via_devicectl(config, home):
    result = devicectl_json(["device", "info", "apps", "--device", config["device_udid"]],
                            timeout=30, log=home / "last-device-validation.log")
    matches = [app for app in result.get("apps", [])
               if app.get("bundleIdentifier") == config["bundle_id"]]
    if not matches:
        raise RenewalError("app_removed", "ShotSkiff is not on this iPhone; it will not be reinstalled automatically.")
    app = matches[0]
    if str(app.get("bundleVersion")) != str(config["build_version"]):
        raise RenewalError("app_changed", "ShotSkiff was updated; revalidate its signing identity before automatic renewal.")
    # CoreDevice reports the app bundle URL rather than libimobiledevice's
    # app and data container paths. Profile-only renewal never changes either.
    return {"CFBundleIdentifier": app.get("bundleIdentifier"),
            "CFBundleVersion": str(app.get("bundleVersion")),
            "CFBundleShortVersionString": app.get("version"),
            "Path": app.get("url")}


def installed_app(config, home, transport="network"):
    if transport == "network":
        try:
            return installed_app_via_libimobiledevice(config, home, transport)
        except RenewalError as error:
            if error.status != "deferred":
                raise
            # Recent Xcode CoreDevice can see a paired iPhone over Wi-Fi when
            # libimobiledevice's network usbmux endpoint cannot. Use Apple's
            # own transport as a fallback; never start a new pairing flow.
            return installed_app_via_devicectl(config, home)
    return installed_app_via_libimobiledevice(config, home, transport)


def installed_app_via_libimobiledevice(config, home, transport):
    args = device_arguments(config, transport)
    # Validate existing trust, never initiate a new pairing workflow.
    validation = ["/opt/homebrew/bin/idevicepair", *args, "validate"]
    code, output = run(validation, timeout=15, log=home / "last-device-validation.log")
    if code and transport == "network" and "no device found" in output.lower():
        # Apple can stop wireless discovery when no Finder device view is open.
        # Start its standard per-user agent (never restart/kill it), only when due.
        run(["/bin/launchctl", "kickstart", "gui/" + str(os.getuid()) + "/com.apple.AMPDevicesAgent"], timeout=5)
        for delay in [2, 4]:
            time.sleep(delay)
            code, output = run(validation, timeout=15, log=home / "last-device-validation.log")
            if not code or "no device found" not in output.lower():
                break
    if code:
        raise RenewalError("deferred", "The existing trusted Wi-Fi connection is unavailable; no pairing prompt was requested.")
    code, output = run(["/opt/homebrew/bin/ideviceinstaller", *args, "list", "--xml", "-b", config["bundle_id"],
                        "-a", "CFBundleIdentifier", "-a", "CFBundleVersion", "-a", "CFBundleShortVersionString",
                        "-a", "Path", "-a", "Container"], timeout=20)
    if code:
        raise RenewalError("deferred", "The iPhone did not answer the app metadata query.")
    try:
        apps = plistlib.loads(output[output.index("<?xml"):].encode())
    except (ValueError, plistlib.InvalidFileException):
        raise RenewalError("error", "The device returned invalid app metadata.")
    matches = [a for a in apps if a.get("CFBundleIdentifier") == config["bundle_id"]]
    if not matches:
        raise RenewalError("app_removed", "SnapBridge is not on this iPhone; it will not be reinstalled automatically.")
    app = matches[0]
    if str(app.get("CFBundleVersion")) != str(config["build_version"]):
        raise RenewalError("app_changed", "SnapBridge was updated; revalidate its signing identity before automatic renewal.")
    return app


def build_fresh(config, home):
    """Request provisioning, then stop Xcode before compiling or signing an app."""
    source = home / "Source"
    for relative, expected in config["source_hashes"].items():
        p = source / relative
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != expected:
            raise RenewalError("source_changed", "The pinned app source changed; refusing unattended provisioning.")
    expected_id = config["team"] + "." + config["bundle_id"]
    roots = [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
             Path.home() / "Library/MobileDevice/Provisioning Profiles"]
    moved = []
    backup = home / "ProfileBackup";backup.mkdir(exist_ok=True)
    process = None
    def stop_build():
        if process is not None and process.poll() is None:
            for sig in [signal.SIGINT, signal.SIGTERM, signal.SIGKILL]:
                try:os.killpg(process.pid, sig)
                except ProcessLookupError:break
                try:process.wait(timeout=3);break
                except subprocess.TimeoutExpired:pass
    try:
        for root in roots:
            for p in root.glob("*.mobileprovision"):
                try:decoded = profile(p)
                except (RenewalError, ValueError, plistlib.InvalidFileException):continue
                if decoded.get("Entitlements", {}).get("application-identifier") == expected_id:
                    target = backup / (root.parent.name + "-" + p.name)
                    shutil.copy2(p, target);p.unlink();moved.append((target, p))
        with tempfile.TemporaryDirectory(prefix="Provision-", dir=home) as work, tempfile.TemporaryFile() as output:
            command = ["/usr/bin/xcodebuild", "-project", str(source / "SnapBridge.xcodeproj"),
                       "-scheme", "SnapBridgePhone", "-configuration", "Release", "-sdk", "iphoneos",
                       "-destination", "generic/platform=iOS", "-derivedDataPath", work,
                       "-allowProvisioningUpdates", "-jobs", "2", "build"]
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 90
            seen = set();candidate = None
            try:
                while time.monotonic() < deadline:
                    for root in roots:
                        for path in root.glob("*.mobileprovision"):
                            stat = path.stat();version = (str(path), stat.st_mtime_ns, stat.st_size)
                            if version in seen:continue
                            try:p = profile(path)
                            except (RenewalError, ValueError, plistlib.InvalidFileException):continue
                            seen.add(version)
                            if p.get("Entitlements", {}).get("application-identifier") != expected_id:continue
                            # A profile is already signed by Apple before Xcode's
                            # later app-code-signing step. Keep the installed app.
                            validate_app(path, config, now() + timedelta(days=5))
                            candidate = home / "Ready.new.mobileprovision"
                            shutil.copy2(path, candidate);candidate.chmod(0o600)
                            break
                        if candidate:break
                    if candidate:break
                    if process.poll() is not None:break
                    time.sleep(0.25)
            finally:
                stop_build()
                output.seek(0);log = output.read().decode(errors="replace")
                (home / "last-build.log").write_text(log[-300000:])
            if candidate:
                ready = home / "Ready.mobileprovision";candidate.replace(ready)
                return ready
            lowered = log.lower()
            if any(x in lowered for x in ["authentication", "session has expired", "no accounts", "sign in", "log in"]):
                raise RenewalError("sign_in_required", "Xcode's Apple account needs sign-in; no credentials are handled by this script.")
            raise RenewalError("build_failed", "Xcode did not issue a fresh profile within the bounded provisioning attempt. See last-build.log.")
    finally:
        stop_build()
        for saved, original in moved:
            if not original.exists():shutil.copy2(saved, original)
        for p in sorted(backup.glob("*.mobileprovision"), key=lambda p:p.stat().st_mtime)[:-4]:p.unlink()


def renew(config, state, home, force=False, transport="network", fresh_profile=False):
    expiry = date(state["installed_expiry"]) if state.get("installed_expiry") else now()
    if not force and expiry > now() + timedelta(hours=48):
        return "healthy", "Signing has more than two days remaining."
    if not force and state.get("retry_after") and date(state["retry_after"]) > now():
        return state.get("status", "deferred"), state.get("message", "Waiting for the next retry.")
    before = installed_app(config, home, transport)
    ready = home / "Ready.mobileprovision"
    if not ready.exists():ready = home / "Ready.app"
    if fresh_profile:
        ready = build_fresh(config, home)
    try:
        p, info = validate_app(ready, config, now() + timedelta(days=5))
    except FileNotFoundError:
        ready = build_fresh(config, home)
        p, info = validate_app(ready, config, now() + timedelta(days=5))
    except RenewalError as error:
        if error.status != "profile_not_extended":
            raise
        ready = build_fresh(config, home)
        p, info = validate_app(ready, config, now() + timedelta(days=5))
    args = device_arguments(config, transport)
    profile_path = ready if ready.suffix == ".mobileprovision" else ready / "embedded.mobileprovision"
    # Only install the signed provisioning profile. Never reinstall the app,
    # prepare developer services, open it, or terminate its running process.
    code, output = run(["/opt/homebrew/bin/ideviceprovision", *args, "install",
                        str(profile_path)], timeout=25,
                       log=home / "last-profile-install.log")
    # Some tool versions can return zero even when the phone rejects a profile.
    installed = not code and "installed successfully" in output.lower()
    installed_with_coredevice = False
    if not installed and transport == "network":
        # Fall back to Apple's CoreDevice profile installer when its Wi-Fi
        # pairing is available but libimobiledevice cannot see that endpoint.
        code, output = run(["/usr/bin/xcrun", "devicectl", "device", "profile", "install",
                            "--device", config["device_udid"], "--type", "provisioning",
                            "--replace-existing", str(profile_path)], timeout=60,
                           log=home / "last-profile-install.log")
        installed = not code and "profile installed successfully" in output.lower()
        installed_with_coredevice = installed
    if not installed:
        raise RenewalError("deferred", "iOS did not confirm the profile update; retry later without changing the app.")
    if installed_with_coredevice:
        # A successful CoreDevice install is an explicit device acknowledgement.
        # Cross-check the UUID when profile listing is available; don't turn a
        # transient list-service failure into a false renewal failure.
        code, output = run(["/usr/bin/xcrun", "devicectl", "device", "profile", "list",
                            "--device", config["device_udid"], "--type", "provisioning",
                            "--search", p["UUID"]], timeout=30,
                           log=home / "last-profile-install.log")
        if not code and p["UUID"].lower() not in output.lower():
            raise RenewalError("error", "CoreDevice installed the profile but its UUID was absent from the device profile list.")
    else:
        with tempfile.TemporaryDirectory(prefix="ProfileCheck-", dir=home) as target:
            code, _ = run(["/opt/homebrew/bin/ideviceprovision", *args, "copy", p["UUID"], target], timeout=25)
            copied = Path(target) / (p["UUID"] + ".mobileprovision")
            if code or not copied.is_file():
                raise RenewalError("error", "The renewed profile could not be read back from the phone.")
            if hashlib.sha256(copied.read_bytes()).digest() != hashlib.sha256(profile_path.read_bytes()).digest():
                raise RenewalError("error", "The device profile differs from the verified signed profile.")
    after = installed_app(config, home, transport)
    unchanged = all(before.get(k) == after.get(k) for k in ["CFBundleIdentifier", "CFBundleVersion", "Path", "Container"]
                    if k in before or k in after)
    if not unchanged:
        raise RenewalError("error", "App metadata changed during profile renewal; automatic renewal is stopped for review.")
    state.update(installed_expiry=stamp(p["ExpirationDate"].replace(tzinfo=UTC)),
                 profile_uuid=p["UUID"], last_success=stamp(now()),
                 installed_build=str(info["CFBundleVersion"]), renewal_mode="profile_only",
                 transport=transport, app_and_data_container_unchanged=True)
    state.pop("retry_after", None)
    return "renewed", "Signing profile renewed without replacing or opening SnapBridge; valid until " + state["installed_expiry"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=DEFAULT_HOME)
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--transport", choices=["network", "usb"], default="network", help="USB is for one-time testing only; scheduled runs always use Wi-Fi")
    parser.add_argument("--force", action="store_true", help="Run the first renewal even if recorded signing is healthy")
    parser.add_argument("--fresh-profile", action="store_true", help="With --force, request a new profile for an end-to-end renewal test")
    args = parser.parse_args()
    if args.fresh_profile and not args.force:
        parser.error("--fresh-profile requires --force")
    home = args.home.expanduser().resolve()
    config = read_json(home / "config.json")
    if not config:
        sys.exit("Run setup_renewal.py first. No renewal configuration exists.")
    state = read_json(home / "state.json")
    if args.status:
        print(json.dumps(state, indent=2))
        return
    with (home / "run.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('{"status":"busy"}')
            return
        previous = state.get("status")
        try:
            status, message = renew(config, state, home, args.force, args.transport, args.fresh_profile)
        except RenewalError as exc:
            status, message = exc.status, exc.message
            if status in ["profile_not_extended", "build_failed", "sign_in_required"]:
                state["retry_after"] = stamp(now() + timedelta(hours=6 if status != "sign_in_required" else 24))
        except Exception as exc:
            status, message = "error", type(exc).__name__ + ": " + str(exc)[:300]
        if status in ["healthy", "renewed"]:
            state["next_run"] = stamp(date(state["installed_expiry"]) - timedelta(hours=48))
        elif status in ["app_removed", "app_changed", "source_changed", "certificate_changed", "error"]:
            state["next_run"] = None
        elif state.get("retry_after") and date(state["retry_after"]) > now():
            state["next_run"] = state["retry_after"]
        else:
            # These retries exist only after a due attempt, not throughout the week.
            state["next_run"] = stamp(now() + timedelta(hours=4))
        state.update(status=status, message=message, last_checked=stamp(now()))
        save_json(home / "state.json", state)
        if status != previous or status == "renewed":
            log = home / "renewal.log"
            if log.exists() and log.stat().st_size > 500000:
                shutil.copy2(log, home / "renewal.previous.log")
                log.write_text("")
            with log.open("a") as f:
                f.write(stamp(now()) + " " + status + " " + message + "\n")
        requests = home / "ScheduleRequests"
        requests.mkdir(exist_ok=True)
        (requests / (str(uuid.uuid4()) + ".request")).write_text(state["last_checked"])
        print(json.dumps(state, indent=2))
        # A separate event-triggered scheduler applies the next calendar date.
        if status in ["error", "source_changed", "app_changed", "certificate_changed", "build_failed", "sign_in_required"]:
            sys.exit(1)


if __name__ == "__main__":
    main()
