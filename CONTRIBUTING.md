# Contributing

Bug reports and focused pull requests are welcome. Please open a GitHub issue before a large change so maintainers can agree on behavior.

Do not include photographs, pairing codes/tokens, iPhone identifiers, provisioning profiles, Apple credentials, local `Local.xcconfig`, or renewal configuration in issues or commits. Use synthetic data for tests and demos.

The Mac and iPhone clients are native Swift. Run `swift test --package-path .`, `python3 scripts/test_clipboard.py`, and `python3 scripts/test_renewal.py` before proposing changes. If you change the project file list, run `python3 scripts/generate_project.py` and include the generated project files.

For camera companion development, use a free Apple Personal Team and your own Xcode login. Never add signing credentials to the repository. macOS release builds are ad-hoc signed and not notarized unless a future release explicitly documents otherwise.

By submitting a contribution, you agree it may be distributed under the repository's MIT license.
