# Automatic iPhone screenshot transfer

On iOS 26 and later, Shortcuts can run an automation when a screenshot is saved to Photos. ShotSkiff exposes **Send Latest Screenshot to Mac** as a background Shortcut action. It reads the original screenshot and sends it to the already paired Mac over ShotSkiff's authenticated local-network channel. The app does not need to be opened for each screenshot.

## One-time setup

1. Install the matching ShotSkiff update on the iPhone and Mac, and open ShotSkiff on the iPhone once so it can use the saved Mac pairing.
2. Open **Shortcuts** on the iPhone, go to **Automation**, tap **+**, and choose **Screenshot** → **Photos**.
3. Choose **Run Immediately**. Add the **Send Latest Screenshot to Mac** action from ShotSkiff, then save the automation.
4. On its first run, allow ShotSkiff to read Photos. The action reads the newest screenshot only; it does not upload the photo library.

After setup, use the usual side-button + volume-up screenshot buttons. Keep the Mac awake with ShotSkiff running and both devices on the same reachable local network. No USB cable or repeated pairing is needed. If the Mac is asleep or unreachable, iOS may not deliver until the next screenshot automation run.

## Notes

- This uses iOS's screenshot event, rather than relying on Finder's Wi-Fi device-management service to remain discoverable indefinitely.
- The transfer sends the original PNG/JPEG bytes and rejects images above ShotSkiff's 16 MB limit rather than silently reducing quality.
- Existing Mac-side AFC screenshot import remains available as a fallback. If both paths see the same original within 10 seconds, the Mac deduplicates identical image bytes.
- Apple requires the user to create personal automations. iOS does not let ShotSkiff silently create or permanently run one on the user's behalf.
