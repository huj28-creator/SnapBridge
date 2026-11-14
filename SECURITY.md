# Security policy

Please report security issues privately through GitHub's **Report a vulnerability** feature if it is enabled for this repository. Otherwise open a minimal issue asking for a private contact route; do not post exploit details, pairing tokens, Apple account data, device identifiers, or photos publicly.

ShotSkiff is local-first. Camera transfer uses authenticated encrypted local transport with a random pairing token stored in each device's Keychain. Screenshot import is limited to the explicitly selected, already trusted iPhone. No image content or pairing credentials are intentionally written to diagnostic logs or sent to a server.

The public Mac binary is ad-hoc signed and is not notarized. Verify its SHA-256 checksum against the release asset before opening it. Do not bypass Gatekeeper or SIP. The app does not silently install software or replace itself with downloaded code.

Free iPhone Personal Team signing expires after seven days. Renewal requires Apple's own signing service, Xcode account access, the existing certificate, and a reachable device; automated renewal is not guaranteed.
