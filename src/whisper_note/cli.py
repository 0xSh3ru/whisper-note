"""
whisper-note CLI entry point.

Execution order:
    1. Parse CLI args
    2. Build Config from env vars, apply CLI overrides
    3. Register the singleton (config.init)
    4. Run preflight checks
    5. Start the application
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from whisper_note import __version__


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="whisper-note",
        description=(
            "Voice-to-markdown note taker.\n"
            "Hold Ctrl+Space to record, release to transcribe and format.\n"
            "Press Esc to quit."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables (all optional — CLI flags take precedence):
  VOICE_NOTES_DIR       Notes output directory           (default: ~/VoiceNotes)
  WHISPER_MODEL         Model name or local path         (default: base)
  WHISPER_COMPUTE_TYPE  Inference precision              (default: int8)
  OPENAI_API_KEY        OpenAI API key for AI formatting
  OPENAI_MODEL          OpenAI chat model                (default: gpt-4o-mini)
  WHISPER_LOG_DIR       Log file directory               (default: ~/.local/share/whisper-note/logs)

Whisper model names:
  tiny | base | small | medium | large-v3
  Named models are downloaded automatically on first use (~74 MB for base).
  Use an absolute path to point to a local model instead.

Examples:
  whisper-note
  whisper-note --model small --notes-dir ~/Documents/notes
  WHISPER_MODEL=large-v3 whisper-note
  GDK_BACKEND=x11 whisper-note           # recommended on GNOME Wayland
        """,
    )

    parser.add_argument(
        "--notes-dir",
        metavar="DIR",
        help="Directory to save notes (overrides VOICE_NOTES_DIR)",
    )
    parser.add_argument(
        "--model",
        metavar="MODEL",
        help=(
            "Whisper model name (tiny/base/small/medium/large-v3) or "
            "absolute path to a local model directory (overrides WHISPER_MODEL)"
        ),
    )
    parser.add_argument(
        "--compute-type",
        metavar="TYPE",
        choices=["int8", "float16", "float32"],
        help="Whisper inference precision — int8 / float16 / float32 (overrides WHISPER_COMPUTE_TYPE)",
    )
    parser.add_argument(
        "--openai-model",
        metavar="MODEL",
        help="OpenAI chat model for formatting (overrides OPENAI_MODEL)",
    )
    parser.add_argument(
        "--log-dir",
        metavar="DIR",
        help="Directory for session log files (overrides WHISPER_LOG_DIR)",
    )
    parser.add_argument(
        "--skip-checks",
        action="store_true",
        help="Skip startup dependency checks (not recommended)",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    # ── Build Config: env vars first, CLI flags override ─────────────────────
    from whisper_note.config import Config, init as config_init

    cfg = Config()

    if args.notes_dir:
        cfg.voice_notes_dir = Path(args.notes_dir).expanduser().resolve()
    if args.model:
        cfg.whisper_model = args.model
    if args.compute_type:
        cfg.whisper_compute_type = args.compute_type
    if args.openai_model:
        cfg.openai_model = args.openai_model
    if args.log_dir:
        cfg.log_dir = Path(args.log_dir).expanduser().resolve()

    config_init(cfg)

    # ── Preflight checks ─────────────────────────────────────────────────────
    if not args.skip_checks:
        from whisper_note.preflight import run_checks
        run_checks(cfg)

    # ── Run ───────────────────────────────────────────────────────────────────
    from whisper_note.main import main as run_app
    run_app()
