# SnapBridge performance — measured on the connected iPhone

After fixing the receiver’s rejected Bonjour registration and enabling direct encrypted transfer, four measured test shots reached the Mac in **0.48–0.55 seconds from shutter press**. The user confirmed that immediately shooting after reopening is fast and stable.

| Shot | Original JPEG | Camera processing | Transfer + Mac receipt | Shutter → receipt |
|---|---:|---:|---:|---:|
| 1 | 2.10 MB | 0.379 s | 0.086 s | 0.479 s |
| 2 | 2.60 MB | 0.403 s | 0.096 s | 0.519 s |
| 3 | 6.41 MB | 0.284 s | 0.241 s | 0.554 s |
| 4 | 3.09 MB | 0.329 s | 0.157 s | 0.502 s |

The earlier slow reopen shot measured 13.02 seconds; only 0.41 seconds was camera processing. It waited for a legacy connection before sending. macOS had rejected the new service registration with DNS NoAuth. The working direct service uses the app’s existing declared Bonjour type and the permanent receiver ID.

The app now sends the camera’s original JPEG without resizing, recompression, or metadata stripping. It resolves the saved destination directly, retains an authenticated connection when iOS permits, and restores it automatically after disconnection. Camera startup and networking overlap. Actual receive progress prevents premature retry of a large photo; a stalled connection is refreshed automatically.

The Mac validates/saves and builds a display thumbnail on a background queue. Original JPEG clipboard data is immediate; full-resolution PNG/TIFF alternatives are lossless and prepared off the popup’s critical path. Mac-only preparation improved from 706.4 to 56.9 ms in a controlled synthetic benchmark. This is not a whole-transfer speedup claim.

Measurements are from this phone and current wireless conditions. Camera processing, network availability, and iOS suspension can affect other runs. Twenty-seven tests cover reconnection, authentication, byte preservation, malformed input, and actual-file cleanup.

Apple references: [Network framework migration and discovery guidance](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework), [peer-to-peer interfaces](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer), [local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
