# SnapBridge implementation plan

Goal: take a photo in a dedicated iPhone camera app and have it appear on this Mac, already copied for pasting into a chat.

1. Build two native Swift apps in one Xcode project: an iPhone camera and a Mac menu bar receiver.
2. Pair once with a six-digit code. Save a random device token in each device’s Keychain; reconnect with that token on later launches. Show a code again only when the user chooses to change devices.
3. Start discovery for the saved Mac alongside camera startup. Maintain authenticated direct TLS/TCP over the LAN; stop discovery while connected. Use encrypted Multipeer Connectivity for initial pairing and fallback. Reconnect automatically without a proximity gate or repeated code.
4. Keep up to ten undelivered photos in an iPhone outbox. Remove each only after a receipt from the Mac; retry after disconnections.
5. Keep the newest 20 photos on the Mac, permanently removing older files automatically; publish the original full-resolution JPEG to the clipboard immediately, with lossless PNG/TIFF compatibility data prepared off the UI thread, and show a centered floating, draggable preview above the current app without taking keyboard focus.
6. Validate the wire protocol and pairing rules with unit tests; compile Mac, simulator, and physical iPhone builds; exercise transfer and reconnection in the simulator.
7. Install the Mac receiver. Sign and install the iPhone app on the connected phone once Xcode account authentication is available.

The iPhone app stays open while taking and sending photos. The saved Mac is the destination until explicitly replaced. Keep a live socket across app switching when iOS permits, finish in-flight delivery in a bounded background task, and automatically restore a dropped socket on return. Preserve the original camera JPEG without resizing or recompressing it. Diagnose delays with bounded per-stage timings; validate reopening, disconnection recovery, byte preservation, and the storage cap.

8. Support both landscape directions using Apple’s rotation coordinator, without re-encoding the photo. Adapt camera controls to the available width.
9. Reveal the Mac setup code after an intentional re-pair request; preserve saved pairing after ordinary network loss.
10. Group successive photos for the lifetime of the popup, display an expandable thumbnail grid, and publish original file attachments together. Closing the popup starts a new group; storage eviction also removes stale attachments.
11. Publish portable source under MIT, with private signing files excluded.
