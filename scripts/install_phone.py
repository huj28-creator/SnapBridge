#!/usr/bin/env python3
"""Build and install SnapBridge on one USB-connected iPhone using Xcode's tools."""
from pathlib import Path
import argparse
import json
import plistlib
import subprocess
import sys
import tempfile
from datetime import timezone

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--device", help="Explicit device identifier if more than one phone is wired")
parser.add_argument("--team", help="Override the development team selected in the project")
parser.add_argument("--build-dir", type=Path, default=root / "build/PhoneDevice")
args = parser.parse_args()
phase = "build"

def run(command, **kwargs):
    subprocess.run(command, check=True, **kwargs)

try:
    with tempfile.TemporaryDirectory(prefix="snapbridge-devices-") as temp:
        listing = Path(temp) / "devices.json"
        run(["xcrun", "devicectl", "list", "devices", "--json-output", str(listing)], stdout=subprocess.DEVNULL)
        devices = json.loads(listing.read_text())["result"]["devices"]
    candidates = []
    for device in devices:
        properties = device.get("properties", {})
        connection = properties.get("connection", device.get("connectionProperties", {}))
        hardware = properties.get("hardware", device.get("hardwareProperties", {}))
        state = properties.get("state", device.get("deviceProperties", {}))
        if connection.get("transportType") == "wired" and hardware.get("deviceType") == "iPhone":
            candidates.append((device["identifier"], state.get("name", "iPhone"), hardware.get("udid", device["identifier"])))
    if args.device:
        device_id = args.device
        destination_id = args.device
        for core_id, _, udid in candidates:
            if args.device in (core_id, udid):
                device_id, destination_id = core_id, udid
                break
    elif len(candidates) == 1:
        device_id, name, destination_id = candidates[0]
        print(f"Installing on {name}.", flush=True)
    else:
        sys.exit("Connect and unlock exactly one iPhone by USB, or pass --device explicitly.")
    build = args.build_dir.resolve()
    command = ["xcodebuild", "-quiet", "-project", str(root / "SnapBridge.xcodeproj"),
               "-scheme", "SnapBridgePhone", "-configuration", "Release", "-sdk", "iphoneos",
               "-destination", f"id={destination_id}", "-derivedDataPath", str(build),
               "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration", "build"]
    if args.team:
        command.append(f"DEVELOPMENT_TEAM={args.team}")
    run(command)
    app = build / "Build/Products/Release-iphoneos/SnapBridgeCamera.app"
    phase = "install"
    run(["xcrun", "devicectl", "device", "install", "app", "--device", device_id, str(app)])
    profile = app / "embedded.mobileprovision"
    if profile.exists():
        decoded = subprocess.run(["security", "cms", "-D", "-i", str(profile)],
                                 capture_output=True, check=False)
        if decoded.returncode == 0:
            expiry = plistlib.loads(decoded.stdout).get("ExpirationDate")
            if expiry:
                local_expiry = expiry.replace(tzinfo=timezone.utc).astimezone()
                print(f"Apple signing is valid until {local_expiry:%B %d, %Y at %I:%M %p %Z}.", flush=True)
    bundle_id = plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"]
    phase = "launch"
    run(["xcrun", "devicectl", "device", "process", "launch", "--device", device_id,
         bundle_id])
    print("Installed. Allow Camera and Local Network access, then pair your Mac once.")
except subprocess.CalledProcessError:
    if phase == "launch":
        sys.exit("App installed. Open it on your iPhone. If iOS requests trust, use Settings → General → VPN & Device Management to trust your developer profile.")
    sys.exit("Installation stopped. If signing failed, sign in under Xcode → Settings → Apple Accounts, then rerun.")
