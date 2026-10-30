#!/usr/bin/env python3
"""Install private, expiry-driven renewal independent of Codex and USB cables."""
from pathlib import Path
from datetime import timezone
import argparse
import hashlib
import io
import json
import os
import plistlib
import shutil
import subprocess
import tarfile
from renew_phone import DEFAULT_HOME, now, profile, save_json, stamp, validate_app
from build_renewal_runner import build_runner


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installed-build", type=Path, required=True,
                        help="The original signed .app last installed on this iPhone")
    parser.add_argument("--ready-build", type=Path, help="An already refreshed build with the same identity")
    parser.add_argument("--device", help="Required when a profile covers more than one iPhone")
    parser.add_argument("--home", type=Path, default=DEFAULT_HOME)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    info = plistlib.loads((args.installed_build / "Info.plist").read_bytes())
    p = profile(args.installed_build)
    devices = p.get("ProvisionedDevices", [])
    device = args.device or (devices[0] if len(devices) == 1 else None)
    if not device or device not in devices:
        parser.error("Choose a device included in the original app's profile.")
    bundle = info["CFBundleIdentifier"]
    suffix = ".snapbridge.camera"
    if not bundle.endswith(suffix):
        parser.error("This setup only supports the SnapBridge camera app.")
    home = args.home.expanduser().resolve()
    if (home / "config.json").exists():
        parser.error("Renewal is already configured; preserve its state and update scripts in place.")
    subprocess.run(["git", "-C", str(root), "diff", "--exit-code", "HEAD", "--",
                    "Shared", "iPhone", "Mac", "Resources", "SnapBridge.xcodeproj"], check=True,
                   stdout=subprocess.DEVNULL)
    home.mkdir(parents=True, exist_ok=True);home.chmod(0o700)
    archive = subprocess.check_output(["git", "-C", str(root), "archive", "HEAD"])
    source = home / "Source";source.mkdir(exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            rel = Path(member.name)
            if rel.parts[0] not in {"Shared", "iPhone", "Mac", "Resources", "SnapBridge.xcodeproj"}:
                continue
            if rel.is_absolute() or ".." in rel.parts or member.issym() or member.islnk():
                raise ValueError("Unexpected archive path")
            target = source / rel
            if member.isdir():target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar.extractfile(member).read())
    team = p["TeamIdentifier"][0]
    (source / "Local.xcconfig").write_text("DEVELOPMENT_TEAM = " + team + "\nSNAPBRIDGE_BUNDLE_PREFIX = " + bundle[:-len(suffix)] + "\n")
    hashes = {str(x.relative_to(source)): hashlib.sha256(x.read_bytes()).hexdigest()
              for x in source.rglob("*") if x.is_file()}
    config = dict(device_udid=device, team=team, bundle_id=bundle,
                  build_version=str(info["CFBundleVersion"]), marketing_version=info["CFBundleShortVersionString"],
                  installed_certificate_sha256=[hashlib.sha256(c).hexdigest() for c in p.get("DeveloperCertificates", [])],
                  expected_profile_entitlements=p.get("Entitlements", {}),
                  source_revision=subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
                  source_hashes=hashes)
    save_json(home / "config.json", config)
    save_json(home / "state.json", dict(installed_expiry=stamp(p["ExpirationDate"].replace(tzinfo=timezone.utc)),
                                      status="configured", next_run=stamp(now()),
                                      message="First in-place renewal has not completed yet."))
    for original, name in [("renew_phone.py", "renew.py"), ("schedule_renewal.py", "schedule.py")]:
        shutil.copy2(root / "scripts" / original, home / name)
    # The scheduler imports the renewal module using its source name.
    shutil.copy2(root / "scripts/renew_phone.py", home / "renew_phone.py")
    if args.ready_build:
        validate_app(args.ready_build, config, now())
        shutil.copytree(args.ready_build, home / "Ready.app", symlinks=True)
    build_runner(home, original_profile=args.installed_build / "embedded.mobileprovision")
    requests = home / "ScheduleRequests";requests.mkdir(exist_ok=True)
    (requests / "initial.request").write_text("configured")
    agents = Path.home() / "Library/LaunchAgents";agents.mkdir(exist_ok=True)
    label = "local.snapbridge.renewal.scheduler"
    path = agents / (label + ".plist")
    path.write_bytes(plistlib.dumps(dict(Label=label,
        ProgramArguments=["/usr/bin/python3", str(home / "schedule.py"), "--home", str(home)],
        WorkingDirectory=str(home), QueueDirectories=[str(requests)], RunAtLoad=True,
        ProcessType="Background", Nice=10, LowPriorityIO=True, ThrottleInterval=30,
        StandardOutPath="/dev/null", StandardErrorPath=str(home / "scheduler-error.log")), sort_keys=False))
    domain = "gui/" + str(os.getuid())
    subprocess.run(["/bin/launchctl", "bootstrap", domain, str(path)], check=True)
    print("Expiry-driven background renewal configured in " + str(home))


if __name__ == "__main__":
    main()
