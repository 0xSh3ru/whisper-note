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

    _check_python_version(errors)
    _check_required_packages(errors, passed)
    _check_gtk(warnings, passed)
    _check_audio_device(errors, passed)
    _check_whisper_model(cfg, errors, warnings, passed)
    _check_notes_dir(cfg, errors, passed)
    _check_log_dir(cfg, warnings, passed)
    _check_openai_key(cfg, warnings)

    for msg in passed:
        print(f"  {_G}✓{_X}  {msg}")
    for msg in warnings:
        print(f"  {_Y}⚠{_X}  {msg}")
    for msg in errors:
        print(f"  {_R}✗{_X}  {msg}")

    print()

    if errors:
        print(
            f"{_R}{_B}Cannot start — {len(errors)} error(s) above must be resolved "
            f"before whisper-note can run.{_X}\n"
        )
        sys.exit(1)

    if warnings:
        print(f"{_Y}Continuing with {len(warnings)} warning(s).{_X}\n")
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
            "     → sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0"
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


def _check_openai_key(cfg: Config, warnings: list[str]) -> None:
    if not cfg.openai_api_key:
        warnings.append(
            "OPENAI_API_KEY is not set — AI formatting is disabled.\n"
            "     Notes will be saved using the raw transcript only.\n"
            "     → export OPENAI_API_KEY=sk-..."
        )
