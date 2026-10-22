# Current validation — version 0.5.0

- Signed Release Mac and physical iPhone builds succeed. Existing app identities and saved pairing are preserved by local signing settings.
- 27 Swift tests pass, including grouping lifetime, duplicate protection, eviction from active groups, all four image orientation cases, authentication, reconnecting, malformed packets, and permanent deletion at the 20-file cap.
- A separate private-pasteboard integration check verifies two ordered original file attachments and full-resolution, pixel-identical PNG/TIFF alternatives for a rotated JPEG. The user's general clipboard is untouched by this automated check.
- Physical-device testing confirmed both landscape directions arrive upright.
- Physical-device/manual UI testing confirmed three successive shots appear in one popup, thumbnails enlarge, one paste attaches all three, and closing the window starts a fresh group.
- Personal signing settings live in ignored `Local.xcconfig`; public defaults and an example support other developers. No photos, pairing tokens, device identifiers, or provisioning files are published.

## Earlier validation history

# Validation — October 21, 2026

- Native Mac and iPhone simulator builds succeeded.
- Signed Release Mac build verified with `codesign --verify --deep --strict` and installed in Applications.
- Signed physical iPhone build installed on the USB-connected iPhone 12 Pro Max running iOS 18.6.2; Developer Mode was already enabled.
- User trusted the development profile, completed initial pairing, took a real photo, and confirmed that it works. The Mac receiver independently showed the real phone connected, permanent pairing saved, and one photo received.
- Eight protocol and pairing unit tests passed with zero failures. Coverage includes malformed input, photo size limits, JPEG validation, version rejection, receipts, first pairing, token revocation, and saved pairing surviving setup-code changes.
- Simulator delivered three JPEGs. Every saved Mac file matched the sender’s bytes exactly.
- A queued photo survived a connection problem and delivered on reconnection.
- Restarted the simulator app with no pairing code supplied. It restored its saved pairing, reconnected, and delivered another photo.
- Mac clipboard contained a PNG image with the expected test dimensions of 1200 × 1500.
- Visually inspected the Mac setup interface. Its floating preview uses a nonactivating panel and supports copying and dragging.
- Removed the simulator’s test pairing before pairing the physical phone. Moved synthetic test photos out of the user’s inbox.

Free Personal Team phone installations expire after seven days. Rebuilding over the same app preserves pairing; do not delete the app first.

The first version is for portrait photography with the app open. Exact physical proximity thresholds, background capture, transfer during device sleep, and long-running behavior across different Wi-Fi networks have not been validated.

## Mac update 0.1.1 — storage limit and centered preview

- Installed the signed Mac update while preserving the existing phone pairing. The iPhone app was left unchanged.
- The Mac keeps at most 20 managed JPEG files. New arrivals and app startup permanently delete the oldest excess files directly from the inbox, without putting copies in Trash.
- Added five filesystem tests: the 21st image deletes the oldest actual file; startup reduces 47 files to the newest 20; cleanup below the limit preserves files; duplicate transfers preserve existing files; cleanup leaves unrelated files and symlinks alone. All 13 tests pass.
- Preview placement now uses the center of the display containing the pointer, with the existing floating, nonactivating panel and support for full-screen Spaces.
- User took another real photo after installing the update and confirmed that the centered popup works above the current app.
- The iPhone continues deleting delivered photos immediately and retaining at most ten undelivered photos. No rolling phone archive was added.

## Performance and automatic connection update 0.3.0

- Signed Release builds succeeded for the Mac and the connected physical iPhone. Installed over the existing apps; saved pairing retained.
- 22 tests pass: protocol/pairing, actual-file retention, full camera JPEG byte preservation, EXIF-aware full-resolution clipboard orientation, encrypted direct transfer, wrong-token rejection, receiver restart recovery, and retaining the authenticated socket across a background-style pause.
- A real slow shot measured 406.7 ms camera processing and 13,017.4 ms shutter-to-receipt. Its trace showed the legacy transport; roughly 10 seconds elapsed before transfer began.
- The new Bonjour service was rejected by macOS with DNS NoAuth despite the Local Network switch being on. Reusing the app’s existing declared service type fixed registration. A stable saved receiver UUID addresses the TLS listener directly, without waiting for a browse list. Peer-to-peer interfaces are enabled for networks where ordinary LAN discovery is unavailable.
- After the registration fix, four fresh physical-phone shots measured 479.5, 519.4, 553.9, and 502.3 ms from shutter press to Mac receipt. Payloads were 2.10–6.41 MB; transfer-to-receipt measured 85.9–240.6 ms. These are observations on this device/network, not a universal latency guarantee. Physical-device testing confirmed fast, stable delivery after closing/reopening and immediately shooting.
- The original camera JPEG is no longer resized or recompressed. Unit tests preserve a 4032 × 3024 original byte for byte. The display thumbnail is separate from the full-resolution saved file and clipboard.
- Mac preparation moved off the UI thread; JPEG clipboard data is immediate, with lossless PNG/TIFF generated asynchronously or on demand. A controlled 2250 × 3000 test measured 706.4 ms old Mac preparation vs 56.9 ms new preparation; that ratio applies to this stage only. Decoded clipboard pixels matched exactly.
- Receive-progress acknowledgments keep large, healthy transfers alive. A genuinely stalled delivery is reconnected after four seconds without receive progress, while retaining the queued original.
- Existing centered popup, 20-photo Mac cap, duplicate receipt protection, and deletion of delivered phone files remain in place. Diagnostic metadata is bounded to 20 shots and 40 connection events. Retry delays increase during a sustained outage and reset on foreground return or successful authentication.
- Uses normal Apple camera/network APIs and development signing. No jailbreaking, system protection changes, or cloud photo upload. Camera use and local wireless transfer have normal battery/thermal costs. iOS controls background suspension; a permanent pairing does not guarantee a socket remains alive after backgrounding or force-quit.

- Final installed builds: Mac 0.3.0 build 6; iPhone 0.3.0 build 5. Both Release builds succeeded and all 22 tests passed after adding outage backoff. Developer diagnostics no longer stream to a terminal; only bounded local metadata files remain. The actual received JPEG dimensions were verified as 4032 × 3024, and the lossless clipboard PNG as 3024 × 4032 after honoring orientation.
