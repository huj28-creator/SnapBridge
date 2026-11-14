# Changelog

## ShotSkiff v0.1.0 — public preview

- Renamed the public product from SnapBridge to ShotSkiff while keeping historical bundle identifiers, local storage paths, Keychain service, and Bonjour service stable for compatibility.
- Added Mac graphical discovery and selection of an already trusted iPhone for screenshot import, opt-in enable/pause controls, a baseline that skips existing photos, and transparent dependency installation consent.
- Added an Apple Silicon DMG build, SHA-256 checksums, and a manual GitHub release update check.
- Added bilingual installation and privacy documentation and a bilingual product website.
- Preserved automatic camera transfer, original image bytes, grouping, clipboard, drag/drop, pairing, and 20-image retention.

### Limitations

- Mac app is ad-hoc signed, not Developer ID signed or notarized. macOS may require Control-click → Open.
- Screenshot capture support needs Python 3 and Homebrew `libimobiledevice`; Homebrew itself is not silently installed.
- Camera companion is installed through Xcode using a user's own free Personal Team. Its provisioning expires after seven days; optional automatic renewal is conditional.
- Only the Apple Silicon Mac build is included and validated. Intel and Windows are not supported in this release.
- iPhone screenshot setup is tested only with an already trusted device connection; direct hardware onboarding test for the new picker remains outstanding.
