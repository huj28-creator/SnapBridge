# Free background renewal

This optional helper renews the signing profile of the SnapBridge app already on your iPhone. It does not install a replacement app, open or terminate SnapBridge, mount a developer disk image, or control the phone’s screen. Profile-only refresh follows the same approach used by [AltStore’s refresh operation](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/RefreshAppOperation.swift).

Apple still issues seven-day profiles for a free Personal Team. The helper renews them automatically; it does not turn free signing into a permanent certificate or remove Apple’s requirements.

## Requirements

- The original signed `.app` that was installed on this iPhone, its signing identity in the Mac login keychain, Xcode signed in to the same account, and this repository checked out at the matching app source revision.
- Homebrew `libimobiledevice` and `ideviceinstaller`: `brew install libimobiledevice ideviceinstaller`. The scripts currently expect Apple Silicon Homebrew at `/opt/homebrew/bin`.
- Initial USB trust and Wi-Fi device management enabled. In Finder, select the connected iPhone and enable **Show this iPhone when on Wi-Fi**, then apply. Alternatively, compile `scripts/enable_wifi.c` against Homebrew’s libraries and run it with the phone’s UDID and `--enable`, once, over its existing trusted USB connection. It changes only the Wi-Fi connection preference.
- A Mac user session logged in and a reachable phone on the same local network for routine renewal. Internet is needed when requesting a fresh profile from Apple.

No Apple password, verification code, or private key is saved in the helper’s configuration. Credentials remain with Xcode and the login keychain.

## Setup

Keep a copy of the signed app from the original Xcode build. Its usual path is inside DerivedData at `Build/Products/Release-iphoneos/SnapBridgeCamera.app`. Configure a renewal installation with:

```sh
python3 scripts/setup_renewal.py --installed-build /absolute/path/to/SnapBridgeCamera.app
```

If the profile includes several devices, also supply `--device YOUR_IPHONE_UDID`. The helper freezes the current committed app source, signing team, bundle identifier, device, certificate hashes, and entitlements in a private directory. The original build must correspond to that source revision. A newer signed build can be supplied with `--ready-build /absolute/path/to/refreshed/SnapBridgeCamera.app` to avoid another first build.

Open `~/Library/Application Support/SnapBridge Renewal/SnapBridge Renewal.app` once. macOS may ask to allow **Local Network** access for **SnapBridge Renewal**. Allow it for the Wi-Fi helper; future runs use that saved permission. The explicit setup check stays alive for at most one minute for this initial permission. [Apple explains why a named background agent needs its own Local Network permission](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

After that permission is granted, trigger the initial background test:

```sh
launchctl kickstart gui/$(id -u)/local.snapbridge.renewal
python3 scripts/renew_phone.py --status
```

Check status again after the background run completes. A successful result has `status: renewed`, `renewal_mode: profile_only`, `transport: network`, and `app_and_data_container_unchanged: true`. An unavailable phone produces a deferred retry, not a pairing prompt or app reinstall. Open SnapBridge and send a photo to confirm the complete workflow on your device.

If signing has more than two days remaining, a normal run reports `healthy` without contacting the phone. To explicitly test the complete early-renewal cycle, run the bundled `SnapBridgeRenewal` executable with `--run-renewal --force --fresh-profile`. This requests another profile from Apple, so use it for initial verification rather than frequent checking.

## Developer trust

iOS developer-trust approval cannot be silently granted by this helper. The first locked-phone profile refresh in testing occurred after the original profile had expired, and the phone subsequently requested manual developer trust despite an unchanged signing certificate. The user re-established trust. Early renewal keeps that same certificate and is scheduled 48 hours before expiration; it does not promise that iOS will never request trust or verification again.

If iOS asks, use **Settings → General → VPN & Device Management → your developer → Trust**.

## Schedule and checks

The renewal job has a single `StartCalendarInterval`, calculated from the verified phone profile’s expiration minus 48 hours, rounded up to the next minute. There is no periodic `StartInterval`. A second small scheduler runs only on a schedule-change request or login and exits. No helper process stays running between deadlines. Missed work can resume after Mac wake or login.

If the phone is missing when a renewal is due, the helper starts Apple’s standard per-user wireless-device agent and makes two brief discovery retries. It does not restart that agent or change trust. If the phone remains unreachable, the next attempt is four hours later. A healthy signature causes no phone or Apple server query. A signing-account failure retries after 24 hours; Apple can still require you to sign back in to Xcode. The helper cannot unlock a phone after a reboot or override iOS security restrictions. Wi-Fi reachability while locked varies with the phone, network, and iOS version.

At renewal time Xcode resolves provisioning for a generic iOS target; the helper captures the fresh Apple-signed profile and immediately cancels the build before app compilation and signing. It does not connect development services to the phone. The helper validates the signing identity, original certificate, device, entitlements, and expiration before sending only the signed `.mobileprovision` through the existing trusted Wi-Fi connection. It reads the profile back and compares its bytes, then checks that the app’s bundle and data-container paths stayed unchanged. A certificate change, app update, removed app, source mismatch, or failed verification stops automatic renewal for review. It never reinstalls an app the user deleted.

The helper runs at background priority through LaunchServices so macOS attributes its saved Local Network permission correctly. It does not inspect screen contents, wait for an idle phone, or open windows during renewal. Profile-only refresh avoids the app replacement that would interrupt a running app. Provisioning requests are bounded to 90 seconds, and the helper exits between deadlines. It does not need to use the installed iPhone app’s private signing key during routine profile refresh.

Local state and bounded logs live in `~/Library/Application Support/SnapBridge Renewal`, accessible only to your Mac account. No phone identifiers, profiles, credentials, or personal configuration belong in the Git repository.

## Disable

```sh
launchctl bootout gui/$(id -u)/local.snapbridge.renewal.scheduler
launchctl bootout gui/$(id -u)/local.snapbridge.renewal
```

Move `local.snapbridge.renewal.plist` and `local.snapbridge.renewal.scheduler.plist` out of `~/Library/LaunchAgents` to keep them disabled after login. Disabling renewal does not remove SnapBridge or its photos.
