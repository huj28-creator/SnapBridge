#!/usr/bin/env python3
"""Build the named Mac agent using the user's existing free development identity."""
from pathlib import Path
import argparse
import json
import plistlib
import re
import shutil
import subprocess


def build_runner(home, source=None, original_profile=None):
    source = source or Path(__file__).with_name("RenewalRunner.swift")
    config = json.loads((home / "config.json").read_text())
    result = subprocess.check_output(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"], text=True)
    identities = re.findall(r'([A-F0-9]{40}) "([^"]+)"', result)
    selected = next((digest for digest, name in identities if "Apple Development:" in name and "(" + config["team"] + ")" in name), None)
    if not selected:
        # Some Personal Team certificate display names contain a person ID.
        # Match the certificate in the original profile without exporting keys.
        app_profile = original_profile or home / "Ready.app/embedded.mobileprovision"
        decoded = plistlib.loads(subprocess.check_output(["/usr/bin/security", "cms", "-D", "-i", str(app_profile)], stderr=subprocess.DEVNULL))
        import hashlib
        allowed = {hashlib.sha1(c).hexdigest().upper() for c in decoded.get("DeveloperCertificates", [])}
        selected = next((digest for digest, _ in identities if digest in allowed), None)
    if not selected:
        raise RuntimeError("No matching Apple Development identity is available in the login keychain.")
    app = home / "SnapBridge Renewal.app"
    contents = app / "Contents";exe = contents / "MacOS/SnapBridgeRenewal"
    exe.parent.mkdir(parents=True, exist_ok=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier="local.snapbridge.renewal", CFBundleName="SnapBridge Renewal",
        CFBundleDisplayName="SnapBridge Renewal", CFBundleExecutable="SnapBridgeRenewal",
        CFBundlePackageType="APPL", CFBundleVersion="1", CFBundleShortVersionString="1.0",
        LSUIElement=True, LSMinimumSystemVersion="14.0",
        NSLocalNetworkUsageDescription="Renew SnapBridge's signing profile on your paired iPhone over Wi-Fi. No photos are read or uploaded.",
        NSBonjourServices=["_apple-mobdev2._tcp"])))
    shutil.copy2(source, home / "RenewalRunner.swift")
    subprocess.run(["/usr/bin/xcrun", "swiftc", str(source), "-o", str(exe)], check=True)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", selected, "--options", "runtime", str(app)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    return app


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home() / "Library/Application Support/SnapBridge Renewal")
    parser.add_argument("--original-profile", type=Path, help="Original installed profile, if Ready.app is not present yet")
    args = parser.parse_args()
    print(build_runner(args.home, original_profile=args.original_profile))
