# SnapBridge

Take a photo on your iPhone. It appears on your Mac, ready to paste with **⌘V**. Keep shooting to paste several originals together.

Native iPhone camera + Mac menu bar receiver. Permanent pairing, encrypted direct transfer, full-resolution JPEGs, portrait and landscape, automatic clipboard, and bounded local storage. MIT licensed.

## Everyday use

Open SnapBridge on your iPhone and take a photo. The Mac receiver runs in the menu bar. Each received photo is saved, copied to the clipboard, and shown in a centered floating preview above the current app. Paste into your chat or drag a photo into it.

**Automatic photo groups:** keep taking photos while the popup is open, and they join one larger grid. Every arrival updates the clipboard with the entire group, ready for one paste as separate image attachments. Click a thumbnail to enlarge it inside the same window. Closing the popup ends that group; the next shot starts fresh. No single/multiple mode switch is required. The group follows the same 20-photo limit as storage. The destination app’s attachment limits and support for pasting files still apply.

Turn the iPhone either way horizontally for landscape capture. The camera controls move beside the preview, and photo orientation is carried in the original JPEG metadata.

**Pairing happens once.** The saved Mac remains the destination until you choose to replace it. The app maintains its connection while open and reconnects automatically after disconnection or relaunch; there is no proximity trigger or manual reconnect step. There is no code to enter for each photo, session, or day. To switch computers, choose **Change paired Mac** in the iPhone connection settings. To replace the phone, choose **Change paired iPhone** on the Mac.

## First installation

Requirements: iOS 17 or later, macOS 14 or later, Xcode, and an Apple account configured for development signing. The Mac receiver is `SnapBridge.app`; the phone’s Home Screen name is also SnapBridge.

1. Clone this repository. Copy `Local.xcconfig.example` to `Local.xcconfig`, then set your Apple development team ID and a unique bundle prefix, such as `com.yourname`. These personal settings are ignored by Git. Open `SnapBridge.xcodeproj` in Xcode.
2. In **Xcode → Settings → Apple Accounts**, sign in. If an existing account says Authentication Expired, refresh it there. Enter credentials in Xcode, never in chat.
3. Select the **SnapBridgePhone** scheme and your connected iPhone. In **Signing & Capabilities**, choose your development team if Xcode asks.
4. Build/run **SnapBridgeMac** on the Mac, and **SnapBridgePhone** on the connected iPhone. If required, enable Developer Mode on the phone and trust the development app in iPhone Settings.
5. Allow Camera and Local Network access. Open the Mac receiver, choose this Mac on the phone, and enter the displayed code **once**.

If re-pairing after choosing **Change paired Mac**, selecting the Mac on the phone requests the setup code locally on the Mac. You can also open **Pair iPhone / Settings…** from the Mac menu bar to reveal it. Ordinary connection drops preserve pairing and never require a new code.

For the first connection, use the same Wi-Fi network, with Wi-Fi and Bluetooth enabled on both devices. The USB cable is needed for initial installation; normal photo transfer uses the local wireless connection. The iPhone app must be open to capture. Like other camera apps, active capture uses battery and may warm the phone; close or leave the app when finished. An in-progress delivery gets a short background completion window. The app retains its authenticated socket when possible; iOS may suspend networking in the background, and it resumes automatically on return. Pending photos remain in its private outbox through disconnects and app restarts.

Once the Mac app is installed in Applications, enable **Start SnapBridge when I log in** if you want it always available in the menu bar.

## Refresh the free iPhone installation

Apple’s free Personal Team signing expires after seven days. An expired app needs refreshed signing before it can open again. This is separate from saved device pairing. [Apple’s account documentation](https://developer.apple.com/help/account/basics/about-your-developer-account)

**Automatic Wi-Fi renewal:** the optional [local renewal helper](docs/renewal.md) refreshes only the provisioning profile, leaving the app and its data in place. It uses a native macOS calendar job two days before the verified expiration date, then exits. It needs no Codex session, paid membership, routine USB cable, or recurring pairing code. Profile renewal has been tested over Wi-Fi with a locked iPhone on iOS 18.6.2; iOS may still require manual developer trust. Availability depends on Apple’s signing service, the original signing certificate, a trusted reachable phone, and a working Xcode account login. See the setup and limitations before enabling it.

For a manual rebuild, connect and unlock the iPhone, then double-click **Refresh iPhone.command** in this folder. Xcode needs a working account login and an internet connection. Keep the same team and bundle identifier; install over the existing app to preserve pairing and pending photos. **Do not delete the iPhone app first.** The script prints the resulting expiration date. Xcode can reuse an existing unexpired profile, so running the manual rebuild early may keep the current expiration date.

## Files and privacy

- Photo transfer uses native SwiftUI, AVFoundation, AppKit, Network.framework, and Multipeer Connectivity; photos stay local. The optional renewal helper uses Xcode and libimobiledevice to request signing profiles from Apple.
- Encrypted direct TLS/TCP over Wi-Fi or an Apple peer-to-peer link, authenticated with the saved random Keychain pairing token. One-time pairing and a fallback connection use encrypted Multipeer Connectivity. Tokens are not published in discovery. The saved Mac’s service is resolved directly without a device-list browse. Retries start quickly after a drop and back off to at most one attempt every four seconds during a persistent outage; background retries pause.
- The camera’s original JPEG is transferred byte for byte, preserving full camera resolution, metadata, and JPEG quality. No resizing or recompression is applied. The Mac prepares a smaller display preview; saved files and clipboard images keep full resolution. PNG/TIFF clipboard alternatives use lossless encoding and honor EXIF orientation.
- Mac photos are stored in `~/Library/Application Support/SnapBridge/Inbox`. **Open received photos** takes you there.
- The Mac keeps only the newest **20 photos**. Older app-managed photo files are permanently removed automatically when a new photo arrives and during startup cleanup. They are not moved to Trash. Export any photos you want to keep elsewhere.
- The current photo group replaces your Mac clipboard automatically; a single image has JPEG and lossless PNG/TIFF clipboard forms, and groups use separate original file attachments. Duplicate retries are acknowledged without replacing it again. A new photo can overwrite another item you copied, as expected for automatic photo copying.
- The iPhone outbox holds at most ten undelivered photos. Delivery is confirmed after the Mac saves a photo, rather than merely after the sender starts a transfer.
- Delivered photos are deleted immediately from the phone's private outbox. The phone's existing behavior is unchanged by the Mac storage limit.
- Tiny local diagnostic files retain timing metadata for at most 20 shots and 40 connection events, with no image content or pairing secrets. It helps distinguish camera processing from connection and transfer delays.
- Resetting pairing preserves received photos. Deleting the iPhone app can remove its queued photos.

## Build and test

`Local.xcconfig` is optional to open the project; public defaults use `com.example`. Select your own team/prefix before installing on a real phone. Regenerating the project preserves the ignored local signing file. No signing keys, credentials, photos, or provisioning profiles belong in Git.

The project includes shared schemes **SnapBridgeMac** and **SnapBridgePhone**. Swift Package Manager runs the protocol tests without building the apps:

```sh
swift test --package-path .
python3 scripts/test_clipboard.py
python3 scripts/test_renewal.py
```

To regenerate the project after changing its file list:

```sh
python3 scripts/generate_project.py
```

The iPhone simulator includes a **Send simulator test photo** button. That button is excluded from physical iPhone builds. Simulator-only environment variables `SNAPBRIDGE_TEST=1` and, on initial pairing only, `SNAPBRIDGE_TEST_CODE=<code>` exercise an automated transfer. Test events and a sample image stay in the simulator app’s Application Support folder. No token is written to that log.

Use `scripts/install_phone.py` (or **Refresh iPhone.command**) to build and install on the one USB-connected iPhone after Xcode sign-in is working. It refuses to choose arbitrarily if multiple phones are wired.

## License

MIT. See [LICENSE](LICENSE). Contributions and bug reports are welcome.
