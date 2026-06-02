"""
Manages the whisper-note environment file at:
  ~/.config/whisper-note/env

All user-facing configuration lives in this file so the systemd service
and the running app share the same source of truth.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ENV_DIR  = Path.home() / ".config" / "whisper-note"
ENV_FILE = ENV_DIR / "env"

# Keys the user is allowed to set via `whisper-note config set`
ALLOWED_KEYS = {
    "WHISPER_MODEL",
    "WHISPER_COMPUTE_TYPE",
    # LLM backend selector
    "WN_LLM_BACKEND",
    # Local backend (llama.cpp + GGUF)
    "WN_LLM_GGUF",
    "WN_LLM_N_CTX",
    "WN_LLM_THREADS",
    "WN_LLM_MAX_TOKENS",
    "WN_LLM_TEMPERATURE",
    # HTTP backend (OpenAI-compatible)
    "WN_LLM_URL",
    "WN_LLM_KEY",
    "WN_LLM_MODEL",
    "WN_LLM_TIMEOUT",
    "VOICE_NOTES_DIR",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
}


def read() -> dict[str, str]:
    """Return the current env file as a key→value dict."""
    if not ENV_FILE.exists():
        return {}
    result: dict[str, str] = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        result[k.strip()] = v.strip()
    return result


def write(values: dict[str, str]) -> None:
    """Overwrite the env file with the given dict (preserves order)."""
    ENV_DIR.mkdir(parents=True, exist_ok=True)
    lines = [f"{k}={v}" for k, v in values.items()]
    ENV_FILE.write_text("\n".join(lines) + "\n")


def set_key(key: str, value: str) -> None:
    """Update a single key in the env file."""
    if key not in ALLOWED_KEYS:
        print(f"Unknown config key: {key!r}", file=sys.stderr)
        print(f"Allowed keys: {', '.join(sorted(ALLOWED_KEYS))}", file=sys.stderr)
        sys.exit(1)
    current = read()
    current[key] = value
    write(current)


def show() -> None:
    """Print the current config to stdout."""
    values = read()
    if not values:
        print(f"No config file found at {ENV_FILE}")
        return
    print(f"Config: {ENV_FILE}\n")
    max_k = max(len(k) for k in values)
    for k, v in values.items():
        # Mask keys that look like secrets
        display_v = "***" if ("KEY" in k or "TOKEN" in k) and v else v
        print(f"  {k:<{max_k}}  =  {display_v}")


def restart_service() -> bool:
    """Reload the systemd service. Returns True on success."""
    try:
        subprocess.run(
            ["systemctl", "--user", "restart", "whisper-note"],
            check=True, timeout=10,
        )
        return True
    except Exception as exc:
        print(f"Could not restart service: {exc}", file=sys.stderr)
        return False
