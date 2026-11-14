# Release validation — ShotSkiff 0.1.0

Validation performed on 2026-11-14 on Apple Silicon macOS with Xcode 27.2.

## Passed locally

- `swift test --package-path .`: 27 tests passed, including original JPEG preservation, landscape orientation, reconnection, encrypted transfer, photo batching, clipboard membership, the 20-image retention boundary, and pairing protocol checks.
- `python3 scripts/test_clipboard.py`: passed; two-item clipboard order and byte identity, plus original JPEG and full-resolution PNG/TIFF behavior, verified.
- `python3 scripts/test_renewal.py`: 18 renewal safety tests passed.
- `scripts/build-release-mac.sh 0.1.0 arm64`: completed; produced an Apple Silicon DMG and SHA-256 sidecar.
- `scripts/verify-release.sh dist/ShotSkiff-macOS-v0.1.0.dmg`: checksum, app bundle signature, and ARM64 architecture verified. The app uses ad-hoc signing and is not notarized.
- Website includes three locally hosted Chinese demo cuts (15, 30, and 46 seconds), English and Chinese captions, and accurate simulator/local-recording disclosures.
- `git diff --check`: passed.

## Not verified in this release environment

- No iPhone was attached during this release pass, so fresh-device onboarding, screenshot import over USB/Wi-Fi, iPhone camera install/capture, renewal on a connected phone, and phone permission-denial flows were not retested on hardware. Earlier development-session reports said camera, landscape, connection recovery, screenshot flow, and grouped paste worked on the owner's devices; those are historical reports, not tests from this release pass.
- No Intel Mac was available; this release is Apple Silicon only.
- A clean macOS user-account first launch and download from the published GitHub release can only be checked after publication. Ad-hoc signature warnings are expected; notarization requires paid Apple Developer Program access and is not claimed.
- GitHub Pages deployed successfully. The first CI workflow was canceled before any test steps because its `macos-14` image had been retired by GitHub. After updating to `macos-15`, GitHub Actions passed the Swift package suite, regenerated-project consistency check, clipboard integration test, and signing-renewal safeguards on commit `0981ba1`.

## Release caveats

- Screenshot setup requires a previously trusted Apple device connection plus Python 3 and Homebrew `libimobiledevice`; the new graphical setup discovers currently reachable trusted devices and can offer to install missing Homebrew dependencies after explicit approval. Wireless visibility is dependent on Apple's device connection state.
- The optional camera companion requires Xcode and the user's free Personal Team. Its provisioning profile expires after seven days; the local helper has prerequisites and cannot automate iOS developer-trust confirmation.
- The promo video uses simulator iPhone footage and sample photographs, not a real-device transfer benchmark. Mac receiver and clipboard portions are locally recorded. Media credits are in `marketing/videos-and-credits.md`.
