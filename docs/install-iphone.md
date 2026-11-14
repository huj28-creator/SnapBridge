# Install the advanced iPhone camera companion

The iPhone companion is optional. The Mac screenshot workflow uses the iPhone's regular screenshot buttons and does not install an iPhone app.

## Requirements and honest signing limits

- A Mac running macOS 14 or later with Xcode installed from Apple.
- iOS 17 or later.
- An Apple Account signed into Xcode under **Xcode → Settings → Accounts**.
- A free **Personal Team** can sign the app, but its development provisioning expires after seven days. A paid Apple Developer Program membership is not required, but the app is not an App Store installation and free signing is temporary.
- Refresh can be automated on the Mac using the existing optional helper if its setup succeeds, the same Xcode account and signing certificate remain available, and the paired phone is reachable. Apple can still require manual trust or intervention. Do not treat automatic refresh as guaranteed.

## Install

1. Install Xcode from Apple and open it once.
2. In Xcode, open **Settings → Accounts**, sign in there, and wait for Xcode to finish loading your Personal Team. Never enter Apple credentials or verification codes into ShotSkiff, Terminal scripts, or chat.
3. Connect and unlock the intended iPhone by USB; tap **Trust This Computer** on the phone. Enable Developer Mode if iOS asks, then restart and confirm.
4. Download the source from GitHub and open `SnapBridge.xcodeproj`. Select **SnapBridgePhone** and the intended device. In **Signing & Capabilities**, choose your own Personal Team and a unique bundle identifier. Keep the same team and bundle ID for later refreshes so iPhone app data and pairing remain intact.
5. Run the iPhone target from Xcode. Allow Camera and Local Network access. Open ShotSkiff on the Mac and pair once using the displayed setup code.
6. For guided command-line installation, the repository's `scripts/install_phone.py` detects connected devices and refuses to choose among multiple phones without an explicit device selection. It uses Xcode's Apple account; it never requests your password itself.

## Optional signing refresh

Double-click **Refresh iPhone.command** for a manual Xcode rebuild over the existing app. Do not delete the iPhone app first. Profile-only automatic renewal is separately documented in [`renewal.md`](renewal.md); its local tests validate safeguards, not Apple's live service. Check the current profile expiry and renewal log after setup. If it fails, connect/unlock the phone and refresh through Xcode. Free signing still expires if renewal does not succeed.

## Limits

Apple does not provide an API for ShotSkiff to silently accept iOS's developer trust prompt. The app cannot automate that on the phone. App installation and signing are governed by Apple's developer tools and policies.
