"""
Build-time requirement checks.

These run during `pip install` (before any package files are copied)
so the user gets a clear failure message early rather than a runtime
crash later.

Checks that CAN run at build time (no system packages needed):
  - Python >= 3.10
  - Linux platform (Ubuntu recommended)

Checks that run at first launch (system packages required):
  - GTK3 bindings  → preflight.py (fatal error)
  - Audio devices  → preflight.py (fatal error)
  - LLM endpoint   → preflight.py (non-fatal warning)
"""
import sys
from pathlib import Path


def _fail(message: str) -> None:
    border = "=" * 60
    raise SystemExit(f"\n{border}\n  whisper-note — installation failed\n{border}\n{message}\n{border}\n")


# ── Python version ────────────────────────────────────────────────────────────
major, minor = sys.version_info[:2]
if (major, minor) < (3, 10):
    _fail(
        f"  Python 3.10 or higher is required.\n"
        f"  You are running Python {major}.{minor}.\n\n"
        f"  Install a supported version:\n"
        f"    sudo apt install python3.12 python3.12-venv"
    )

# ── Platform ──────────────────────────────────────────────────────────────────
if sys.platform != "linux":
    _fail(
        f"  whisper-note is for Linux (Ubuntu) only.\n"
        f"  Detected platform: {sys.platform}"
    )

# ── Ubuntu check (soft — warns but does not block on other distros) ───────────
try:
    os_release = Path("/etc/os-release").read_text()
    if "ubuntu" not in os_release.lower():
        distro = next(
            (l.split("=")[1].strip('" \n') for l in os_release.splitlines()
             if l.startswith("PRETTY_NAME")),
            "unknown"
        )
        print(
            f"\n  ⚠  whisper-note is tested on Ubuntu only.\n"
            f"     Detected: {distro}\n"
            f"     Proceed at your own risk — some features may not work.\n"
        )
except Exception:
    pass  # /etc/os-release missing — skip check


from setuptools import setup  # noqa: E402  (import after checks)
setup()
