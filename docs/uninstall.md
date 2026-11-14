# Uninstall ShotSkiff

1. Choose **Quit ShotSkiff** from its menu-bar icon.
2. Remove `ShotSkiff.app` from Applications.
3. Optional: remove `~/Library/Application Support/SnapBridge/Inbox` to delete received images (up to 20). This permanently deletes them. Export anything you want first.
4. Optional: remove `~/Library/Application Support/SnapBridge` to remove screenshot-device selection and diagnostic/renewal state. This does not reset the Mac Keychain pairing record.
5. To clear camera pairing, reopen ShotSkiff before removing it and choose **Change paired iPhone… → Reset pairing**. This intentionally revokes trusted phone tokens.
6. Optional: disable the renewal helper using its documented command in [`renewal.md`](renewal.md). Do not remove Xcode or Homebrew if other apps use them.

This procedure does not modify iPhone photos outside ShotSkiff's private outbox and does not delete the iPhone companion. Remove that app from the iPhone separately if desired.
