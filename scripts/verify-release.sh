#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-$ROOT/dist/ShotSkiff-macOS-v0.1.0.dmg}"
test -f "$DMG"
shasum -a 256 -c "$DMG.sha256"
MOUNT="$(mktemp -d)"
trap 'hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rm -rf "$MOUNT"' EXIT
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$DMG"
test -d "$MOUNT/ShotSkiff.app"
test -L "$MOUNT/Applications"
codesign --verify --deep --strict "$MOUNT/ShotSkiff.app"
ARCHS="$(lipo -archs "$MOUNT/ShotSkiff.app/Contents/MacOS/SnapBridge")"
echo "DMG verified: $ARCHS; ad-hoc signed; not notarized."
