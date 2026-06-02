"""
whisper-note CLI entry point.

Subcommands:
  (none)           Start the application (default)
  config show      Print current configuration
  config set K=V   Update a config key and restart service
  config restart   Restart the service
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Force pynput onto the X11/XRecord backend before it is imported anywhere.
# On GNOME Wayland, WAYLAND_DISPLAY is set in the session environment and
# pynput silently switches to its Wayland backend, which blocks global
# hotkeys.  Unsetting it here makes pynput use XWayland where XRecord works.
os.environ.pop("WAYLAND_DISPLAY", None)

from whisper_note import __version__


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="whisper-note",
        description=(
            "Voice-to-markdown note taker.\n"
            "Hold Ctrl+Alt+Space to record, release to transcribe and format.\n"
            "Press Esc to quit."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Config keys (edit with 'whisper-note config set KEY=VALUE'):
  WHISPER_MODEL         Whisper model: tiny/base/small/medium/large-v3 or a path
  WHISPER_COMPUTE_TYPE  Precision: int8 / float16 / float32
  WN_LLM_BACKEND        Formatter backend: local (default) / http

  Local backend (llama.cpp + GGUF — fully on-device, no server):
    WN_LLM_GGUF         Path to the GGUF model file
    WN_LLM_N_CTX        Context window (default 8192)
    WN_LLM_THREADS      CPU threads (default 4)
    WN_LLM_MAX_TOKENS   Max output tokens (default 2048)
    WN_LLM_TEMPERATURE  Sampling temperature (default 0.2)

  HTTP backend (OpenAI-compatible — Ollama / OpenAI / Claude):
    WN_LLM_URL          LLM API base URL
    WN_LLM_KEY          LLM API key
    WN_LLM_MODEL        LLM model name
    WN_LLM_TIMEOUT      Request timeout in seconds

  VOICE_NOTES_DIR       Notes output directory

Examples:
  whisper-note
  whisper-note --model small
  whisper-note config show
  whisper-note config set WN_LLM_GGUF=~/models/qwen/qwen2.5-1.5b-instruct-q4_k_m.gguf
  whisper-note config set WN_LLM_BACKEND=http
  whisper-note config set WN_LLM_MODEL=gpt-4o-mini
  whisper-note config set WN_LLM_URL=https://api.openai.com/v1
        """,
    )

    sub = parser.add_subparsers(dest="command")

    # ── config subcommand ────────────────────────────────────────────────────
    cfg_p = sub.add_parser("config", help="View or change configuration")
    cfg_sub = cfg_p.add_subparsers(dest="config_action")

    cfg_sub.add_parser("show", help="Print current config")
    cfg_sub.add_parser("restart", help="Restart the whisper-note service")

    set_p = cfg_sub.add_parser("set", help="Set a config value  (KEY=VALUE)")
    set_p.add_argument("assignment", metavar="KEY=VALUE",
                       help="e.g. WN_LLM_MODEL=gpt-4o-mini")

    # ── run flags ────────────────────────────────────────────────────────────
    parser.add_argument("--notes-dir",    metavar="DIR")
    parser.add_argument("--model",        metavar="MODEL")
    parser.add_argument("--compute-type", metavar="TYPE",
                        choices=["int8", "float16", "float32"])
    parser.add_argument("--log-dir",      metavar="DIR")
    parser.add_argument("--llm-backend",  metavar="BACKEND",
                        choices=["local", "http"],
                        help="Formatter backend (overrides WN_LLM_BACKEND)")
    parser.add_argument("--llm-gguf",     metavar="PATH",
                        help="Local GGUF model path (overrides WN_LLM_GGUF)")
    parser.add_argument("--llm-model",    metavar="MODEL",
                        help="HTTP-backend LLM model (overrides WN_LLM_MODEL)")
    parser.add_argument("--skip-checks",  action="store_true")
    parser.add_argument("--version",      action="version",
                        version=f"%(prog)s {__version__}")

    return parser


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = _build_parser()
    args   = parser.parse_args()

    # ── config subcommand (no app startup needed) ─────────────────────────────
    if args.command == "config":
        from whisper_note.config_manager import show, set_key, restart_service

        action = getattr(args, "config_action", None)

        if action == "show":
            show()

        elif action == "set":
            if "=" not in args.assignment:
                print("Usage: whisper-note config set KEY=VALUE", file=sys.stderr)
                sys.exit(1)
            key, _, value = args.assignment.partition("=")
            set_key(key.strip(), value.strip())
            print(f"  Updated {key.strip()} = {value.strip()!r}")
            print("  Restarting service…")
            ok = restart_service()
            if ok:
                print("  Service restarted.")

        elif action == "restart":
            print("Restarting whisper-note service…")
            restart_service()

        else:
            parser.parse_args(["config", "--help"])

        return

    # ── Normal app startup ────────────────────────────────────────────────────
    from whisper_note.config import Config, init as config_init

    cfg = Config()

    if args.notes_dir:
        cfg.voice_notes_dir = Path(args.notes_dir).expanduser().resolve()
    if args.model:
        cfg.whisper_model = args.model
    if args.compute_type:
        cfg.whisper_compute_type = args.compute_type
    if args.log_dir:
        cfg.log_dir = Path(args.log_dir).expanduser().resolve()
    if args.llm_backend:
        cfg.llm_backend = args.llm_backend
    if args.llm_gguf:
        cfg.llm_gguf_path = Path(args.llm_gguf).expanduser()
    if args.llm_model:
        cfg.llm_model = args.llm_model

    config_init(cfg)

    if not args.skip_checks:
        from whisper_note.preflight import run_checks
        run_checks(cfg)

    from whisper_note.main import main as run_app
    run_app()
