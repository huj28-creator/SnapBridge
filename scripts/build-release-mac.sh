#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
ARCH="${2:-arm64}"
OUT="$ROOT/dist"
BUILD="$ROOT/build/release-$ARCH"
APP="$BUILD/Build/Products/Release/SnapBridge.app"
STAGE="$BUILD/dmg-root"
NAME="ShotSkiff-macOS-v$VERSION"

case "$ARCH" in arm64|x86_64) ;; *) echo "Architecture must be arm64 or x86_64." >&2; exit 2 ;; esac
mkdir -p "$OUT"
xcodebuild -quiet -project "$ROOT/SnapBridge.xcodeproj" -scheme SnapBridgeMac \
  -configuration Release -sdk macosx -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD" ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" build
test -d "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ShotSkiff" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ShotSkiff" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ACTUAL_ARCH="$(lipo -archs "$APP/Contents/MacOS/SnapBridge")"
if [[ "$ACTUAL_ARCH" != "$ARCH" ]]; then echo "Expected $ARCH, got $ACTUAL_ARCH." >&2; exit 1; fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/ShotSkiff.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<EOF
ShotSkiff v$VERSION for macOS ($ARCH)

Drag ShotSkiff.app to Applications, then open it.
This build is ad-hoc signed and is not notarized. If macOS blocks it, Control-click the app in Applications, choose Open, then confirm Open. If that option is unavailable, use System Settings > Privacy & Security > Open Anyway after your first launch attempt.
Do not disable Gatekeeper or System Integrity Protection.

Screenshot importing uses Python 3 and Homebrew's libimobiledevice. The app explains this before installation. The separate iPhone camera companion is installed through Xcode with your own free Personal Team.
EOF
DMG="$OUT/$NAME.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "ShotSkiff $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
cat > "$OUT/$NAME.json" <<EOF
{
  "product": "ShotSkiff",
  "version": "$VERSION",
  "sourceRevision": "$(git -C "$ROOT" rev-parse HEAD)",
  "architecture": "$ARCH",
  "minimumMacOS": "14.0",
  "signing": "ad-hoc; not notarized",
  "artifact": "$NAME.dmg",
  "sha256": "$(awk '{print $1}' "$DMG.sha256")"
}
EOF
echo "Built $DMG ($ARCH; ad-hoc signed, not notarized)."
