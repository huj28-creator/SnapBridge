#!/usr/bin/env python3
"""Validate single-image and multi-file clipboard formats on a private macOS pasteboard."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="snapbridge-clipboard-") as temp:
    executable = Path(temp) / "clipboard-test"
    subprocess.run(["swiftc", "-O", str(root / "Shared/WireProtocol.swift"),
                    str(root / "Shared/PhotoProcessing.swift"), str(root / "Mac/PhotoClipboard.swift"),
                    str(root / "Tests/ClipboardIntegration/main.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
