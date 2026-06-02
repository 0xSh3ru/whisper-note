"""
Startup validation.

Checks every hard and soft requirement before the application starts.
Prints a clear, actionable report and exits on fatal problems.
Warnings are printed but do not block startup.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from whisper_note.config import Config

# ANSI colours — degrade gracefully if the terminal doesn't support them
_NO_COLOR = not sys.stdout.isatty()
_R = "" if _NO_COLOR else "\033[91m"       # red
_Y = "" if _NO_COLOR else "\033[93m"       # yellow
_G = "" if _NO_COLOR else "\033[92m"       # green
_B = "" if _NO_COLOR else "\033[1m"        # bold
_X = "" if _NO_COLOR else "\033[0m"        # reset

_KNOWN_MODELS = frozenset({
    "tiny", "tiny.en",
    "base", "base.en",
    "small", "small.en",
    "medium", "medium.en",
    "large-v1", "large-v2", "large-v3",
    "distil-large-v2", "distil-medium.en", "distil-small.en",
})

_REQUIRED_PACKAGES = {
    "faster_whisper": "faster-whisper",
    "openai":         "openai",
    "sounddevice":    "sounddevice",
    "soundfile":      "soundfile",
    "numpy":          "numpy",
    "pynput":         "pynput",
}


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def run_checks(cfg: Config) -> None:
    """
    Run all checks.  Prints a status report, then either continues or exits.
    """
    print(f"\n{_B}whisper-note — startup checks{_X}\n")

    errors:   list[str] = []
    warnings: list[str] = []
    passed:   list[str] = []

    llm_errors: list[str] = []   # red but non-fatal — app still saves raw notes

    _check_python_version(errors)
    _check_required_packages(errors, passed)
    _check_gtk(warnings, passed)
    _check_audio_device(errors, passed)
    _check_whisper_model(cfg, errors, warnings, passed)
    _check_notes_dir(cfg, errors, passed)
    _check_log_dir(cfg, warnings, passed)
    _check_llm(cfg, llm_errors, passed)

    for msg in passed:
        print(f"  {_G}✓{_X}  {msg}")
    for msg in warnings:
        print(f"  {_Y}⚠{_X}  {msg}")
    for msg in llm_errors:
        print(f"  {_R}✗{_X}  {msg}")
    for msg in errors:
        print(f"  {_R}✗{_X}  {msg}")

    print()

    if errors:
        print(
            f"{_R}{_B}Cannot start — {len(errors)} error(s) above must be resolved "
            f"before whisper-note can run.{_X}\n"
        )
        sys.exit(1)

    non_fatal = warnings + llm_errors
    if non_fatal:
        note = "  (notes will be saved as raw transcripts without AI formatting)" if llm_errors else ""
        print(f"{_Y}Continuing with {len(non_fatal)} warning(s).{_X}{note}\n")
    else:
        print(f"{_G}All checks passed.{_X}\n")


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

def _check_python_version(errors: list[str]) -> None:
    major, minor = sys.version_info[:2]
    if (major, minor) < (3, 10):
        errors.append(
            f"Python 3.10+ required, running {major}.{minor}.\n"
            "     → https://www.python.org/downloads/"
        )


def _check_required_packages(errors: list[str], passed: list[str]) -> None:
    missing: list[str] = []
    for module, pip_name in _REQUIRED_PACKAGES.items():
        try:
            __import__(module)
        except ImportError:
            missing.append(pip_name)

    if missing:
        errors.append(
            f"Missing packages: {', '.join(missing)}\n"
            f"     → pip install {' '.join(missing)}"
        )
    else:
        passed.append("All required Python packages present")


def _check_gtk(warnings: list[str], passed: list[str]) -> None:
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk  # noqa: F401
        passed.append("GTK3 bindings present (status window enabled)")
    except Exception:
        warnings.append(
            "GTK3 bindings not found — running in console mode (no status window).\n"
            "     GTK3 is a system package; it cannot be installed via pip alone.\n"
            "     Fix in two steps:\n"
            "       1. sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0\n"
            "       2. Recreate your venv with system packages:\n"
            "            python3 -m venv --system-site-packages <venv-path>\n"
            "            pip install whisper-note"
        )


def _check_audio_device(errors: list[str], passed: list[str]) -> None:
    try:
        import sounddevice as sd
        devices = sd.query_devices()
        inputs = [d for d in devices if d["max_input_channels"] > 0]
        if not inputs:
            errors.append(
                "No audio input device found.\n"
                "     → Connect a microphone and ensure it is recognised by the OS.\n"
                "     → Check: arecord -l"
            )
        else:
            names = ", ".join(d["name"] for d in inputs[:3])
            suffix = f" (+{len(inputs) - 3} more)" if len(inputs) > 3 else ""
            passed.append(f"Audio input: {names}{suffix}")
    except Exception as exc:
        errors.append(
            f"Cannot query audio devices: {exc}\n"
            "     → sudo apt install portaudio19-dev libsndfile1\n"
            "     → pip install sounddevice soundfile"
        )


def _check_whisper_model(
    cfg: Config,
    errors: list[str],
    warnings: list[str],
    passed: list[str],
) -> None:
    model = cfg.whisper_model
    p = Path(model)

    # Treat as a file-system path if it contains a separator or is absolute
    if p.is_absolute() or "/" in model or "\\" in model:
        if p.exists():
            passed.append(f"Local Whisper model: {p}")
        else:
            errors.append(
                f"Local Whisper model not found: {p}\n"
                "     → Supply a valid directory path or use a named model "
                "(tiny / base / small / medium / large-v3)."
            )
        return

    # Named model
    if model in _KNOWN_MODELS:
        passed.append(
            f"Whisper model: {model!r}  "
            "(downloads automatically on first use if not cached)"
        )
    else:
        warnings.append(
            f"Unrecognised Whisper model name: {model!r}.\n"
            f"     Known names: {', '.join(sorted(_KNOWN_MODELS))}\n"
            "     faster-whisper will attempt to resolve it from HuggingFace Hub."
        )


def _check_notes_dir(cfg: Config, errors: list[str], passed: list[str]) -> None:
    d = cfg.voice_notes_dir
    try:
        d.mkdir(parents=True, exist_ok=True)
        probe = d / ".write_probe"
        probe.touch()
        probe.unlink()
        passed.append(f"Notes directory writable: {d}")
    except (PermissionError, OSError) as exc:
        errors.append(
            f"Notes directory not writable: {d}\n"
            f"     Error: {exc}\n"
            f"     → mkdir -p {d}  or  export VOICE_NOTES_DIR=/writable/path"
        )


def _check_log_dir(cfg: Config, warnings: list[str], passed: list[str]) -> None:
    d = cfg.log_dir
    try:
        d.mkdir(parents=True, exist_ok=True)
        probe = d / ".write_probe"
        probe.touch()
        probe.unlink()
        passed.append(f"Log directory writable: {d}")
    except (PermissionError, OSError) as exc:
        warnings.append(
            f"Log directory not writable: {d} ({exc})\n"
            "     → Logs will fall back to a temporary directory."
        )


def _check_llm(cfg: Config, llm_errors: list[str], passed: list[str]) -> None:
    """
    Verify the configured LLM endpoint is reachable and the key is accepted.
    Uses client.models.list() — a lightweight GET with no token generation.
    Non-fatal: app continues and saves raw transcripts if LLM is unavailable.
    """
    try:
        import httpx
        from openai import OpenAI, AuthenticationError, APIConnectionError

        client = OpenAI(
            base_url=cfg.llm_url,
            api_key=cfg.llm_key,
            max_retries=0,
            default_headers={"anthropic-version": "2023-06-01"},
            http_client=httpx.Client(
                timeout=httpx.Timeout(connect=5.0, read=8.0, write=5.0, pool=5.0)
            ),
        )
        client.models.list()
        passed.append(
            f"LLM ready: {cfg.llm_model}  →  {cfg.llm_url}"
        )

    except AuthenticationError:
        llm_errors.append(
            f"LLM authentication failed — key rejected by {cfg.llm_url}\n"
            f"     Model : {cfg.llm_model}\n"
            "     → Check WN_LLM_KEY is correct for this endpoint."
        )
    except APIConnectionError:
        llm_errors.append(
            f"LLM not reachable — cannot connect to {cfg.llm_url}\n"
            f"     Model : {cfg.llm_model}\n"
            "     → Is the server running?  Check WN_LLM_URL."
        )
    except Exception as exc:
        llm_errors.append(
            f"LLM check failed: {exc}\n"
            f"     URL   : {cfg.llm_url}\n"
            f"     Model : {cfg.llm_model}"
        )
