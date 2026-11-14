# Privacy

ShotSkiff does not require an account and includes no advertising, analytics, or cloud photo upload. Images travel locally between a user's devices.

## Images and metadata

The camera companion transmits the original JPEG without resizing or recompression and preserves its embedded metadata. That metadata can include location if the iPhone camera recorded it. Screenshot PNG originals are also kept intact. Received image bytes are saved in the local Mac inbox and replace the clipboard when delivered.

The Mac keeps no more than 20 app-managed images. Older files are permanently deleted automatically. The screenshot reader monitors only new screenshot candidates on a device the user explicitly selects; it skips the existing library baseline and does not import the whole Photos library.

## Permissions and local records

Camera and Local Network permissions are used by the optional iPhone camera workflow. The screenshot workflow uses the Mac's trusted Apple device pairing and Python/libimobiledevice helper. Pairing tokens are stored in Keychain. Local diagnostics keep bounded timing and connection metadata, not image bytes or tokens; they are not transmitted to ShotSkiff.

The optional free-signing renewal helper communicates with Apple/Xcode signing tools and the paired phone. It does not read or upload photos. Apple account authentication remains in Apple's own tools.

## Contact

Report privacy questions through [GitHub Issues](https://github.com/huj28-creator/SnapBridge/issues). Please do not post private images, identifiers, credentials, or pairing material.
