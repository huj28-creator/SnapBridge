# Install ShotSkiff on your Mac

ShotSkiff's easiest path imports new iPhone screenshots. You do **not** need to install a ShotSkiff app on the iPhone for this workflow.

## 1. Download and install

1. Download [ShotSkiff for macOS](https://github.com/huj28-creator/SnapBridge/releases/latest).
2. Open the downloaded DMG.
3. Drag **ShotSkiff.app** onto the **Applications** shortcut in that window.
4. Open Applications and double-click ShotSkiff.
5. This free build is not notarized. If macOS says it cannot verify the developer, control-click ShotSkiff in Applications and choose **Open**, then confirm **Open**. If needed, make one blocked launch attempt, then open **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper or SIP.

## 2. Connect the iPhone

1. Connect the iPhone to the Mac using USB. Unlock the phone.
2. If asked on the phone, tap **Trust This Computer** and enter its passcode.
3. In ShotSkiff, open **Pair iPhone / Settings** and choose the iPhone by its device name. If several phones are connected, select the intended one yourself.
4. If screenshot support is missing, ShotSkiff explains its Python 3 and Homebrew `libimobiledevice` requirements. The install button asks before running `brew install libimobiledevice`. Homebrew is not silently installed. If you do not already have Homebrew, install it from [brew.sh](https://brew.sh), then reopen ShotSkiff and choose **Refresh iPhones**.
5. Choose **Enable importing**. The app skips existing images, starts monitoring for new screenshots, and registers ShotSkiff to launch at login. It retries the existing trusted Wi-Fi connection and refreshes macOS device discovery after disconnects.
6. Press the iPhone's normal side-button + volume-up screenshot buttons. Allow the screenshot to finish saving. It should appear in the floating preview on the Mac.

When available, ShotSkiff can use the iPhone's previously trusted Wi-Fi device connection after initial USB trust. Wireless access is not available in every network/device state. Reconnect by USB if the phone does not appear.

## Use the image

Click **Copy**, press **⌘V** in a destination app, or drag an image from the preview. Several received images stay together in one window and can be copied as a group. Destination apps decide whether they accept multiple image files, so drag individual images if group paste is unsupported. Every received image replaces the Mac clipboard.

## Storage and privacy

The Mac inbox is `~/Library/Application Support/SnapBridge/Inbox`. ShotSkiff keeps at most 20 app-managed images there; the oldest is permanently deleted when the limit is exceeded. It does not upload images. Screenshot monitoring reads only new screenshot candidates from the explicitly selected trusted iPhone. The camera workflow requires the optional iPhone companion described in [the advanced setup guide](install-iphone.md).

To pause importing, choose **Pause importing** in ShotSkiff settings. ShotSkiff remains available from the menu bar while the Mac session is running; login startup can be disabled in **System Settings → General → Login Items**. To uninstall, quit ShotSkiff, remove it from Applications, and optionally remove its inbox and preferences. See [Uninstalling](uninstall.md) before deleting data.

## Troubleshooting

- **iPhone is missing:** unlock it, reconnect USB, tap Trust if asked, then choose **Refresh iPhones**.
- **Trust prompt did not appear:** unlock the phone and reconnect the cable; on iPhone use Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy only if you deliberately want to reset trust decisions (this affects other trusted computers too).
- **Screenshot does not arrive:** confirm importing is enabled for the right phone, ShotSkiff is running in the menu bar, and Python 3 and `libimobiledevice` are installed. The receiver retries trusted Wi-Fi discovery automatically; reconnect by USB only if macOS has lost the trust pairing.
- **Wi-Fi import is unavailable:** use USB. Wi-Fi relies on Apple's existing trusted device connection and may not be reachable.
- **Transfer delayed:** a locked phone, large/busy photo library, wireless link, or device-service reconnect can delay the original. The preview is ready only after the full PNG arrives.
- **Camera companion disconnected:** open the companion on the phone and Mac, allow Local Network access on both, and verify they can reach each other on the local network. The Mac receiver retries automatically.
- **Several photos won't paste together:** the destination app may not accept multiple file attachments through the clipboard. Try dragging from the group window.

## Advanced camera companion

For camera capture inside a native iPhone app, install the Mac receiver first, then follow [Install the iPhone companion](install-iphone.md). This requires Xcode and your own Apple Account. Free Personal Team app signing expires after seven days; automatic refresh is optional and conditional, and iOS may still require trust again.
