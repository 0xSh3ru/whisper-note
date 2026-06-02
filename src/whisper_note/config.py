"""
Runtime configuration.

All settings derive from environment variables so the binary ships with no
hardcoded paths.  CLI flags (applied in cli.py) override env vars.

Other modules must call config.get() inside functions — never at import time —
so the singleton is always populated before it is read.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


# ---------------------------------------------------------------------------
# Default helpers
# ---------------------------------------------------------------------------

def _xdg_data_home() -> Path:
    """XDG_DATA_HOME, falling back to the spec-compliant default."""
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))


def _default_notes_dir() -> Path:
    return Path(os.environ.get("VOICE_NOTES_DIR", Path.home() / "VoiceNotes"))


def _default_log_dir() -> Path:
    return Path(
        os.environ.get(
            "WHISPER_LOG_DIR",
            _xdg_data_home() / "whisper-note" / "logs",
        )
    )


# ---------------------------------------------------------------------------
# Config dataclass
# ---------------------------------------------------------------------------

@dataclass
class Config:
    # ── Notes output ─────────────────────────────────────────────────────────
    voice_notes_dir: Path = field(default_factory=_default_notes_dir)

    # ── Whisper ───────────────────────────────────────────────────────────────
    # Named model (tiny/base/small/medium/large-v3) → auto-downloaded on first
    # use and cached in ~/.cache/huggingface/hub/.
    # Absolute or relative path → uses a local model directory directly.
    # Default is the local faster-whisper-small directory (on-device, no download).
    whisper_model: str = field(
        default_factory=lambda: os.environ.get(
            "WHISPER_MODEL",
            str(Path("~/models/faster-whisper-small").expanduser()),
        )
    )
    whisper_compute_type: str = field(
        default_factory=lambda: os.environ.get("WHISPER_COMPUTE_TYPE", "int8")
    )
    whisper_beam_size: int = 5

    # ── Audio ─────────────────────────────────────────────────────────────────
    sample_rate: int = 16000

    # ── LLM formatter ──────────────────────────────────────────────────────────
    # Two backends:
    #   "local" (default) → in-process llama.cpp loading a local GGUF file.
    #                        Fully on-device, no server required.  See llm_gguf_path.
    #   "http"            → OpenAI-compatible endpoint (Ollama / OpenAI / Claude).
    #                        Configured via llm_url + llm_key + llm_model.
    llm_backend: str = field(
        default_factory=lambda: os.environ.get("WN_LLM_BACKEND", "local").strip().lower()
    )

    # ── Local backend (llama.cpp + GGUF) ───────────────────────────────────────
    llm_gguf_path: Path = field(
        default_factory=lambda: Path(
            os.environ.get(
                "WN_LLM_GGUF",
                "~/models/qwen/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            )
        ).expanduser()
    )
    llm_n_ctx: int = field(
        default_factory=lambda: int(os.environ.get("WN_LLM_N_CTX", "8192"))
    )
    llm_n_threads: int = field(
        default_factory=lambda: int(os.environ.get("WN_LLM_THREADS", "4"))
    )
    llm_max_tokens: int = field(
        default_factory=lambda: int(os.environ.get("WN_LLM_MAX_TOKENS", "2048"))
    )
    llm_temperature: float = field(
        default_factory=lambda: float(os.environ.get("WN_LLM_TEMPERATURE", "0.2"))
    )

    # ── HTTP backend (OpenAI-compatible — Ollama, OpenAI, Claude) ──────────────
    # Switch provider by changing WN_LLM_URL + WN_LLM_KEY + WN_LLM_MODEL.
    # No code changes needed — all three speak the same API.
    llm_url: str = field(
        default_factory=lambda: os.environ.get("WN_LLM_URL", "http://127.0.0.1:11434/v1")
    )
    llm_key: str = field(
        default_factory=lambda: os.environ.get("WN_LLM_KEY", "ollama")
    )
    llm_model: str = field(
        default_factory=lambda: os.environ.get("WN_LLM_MODEL", "qwen3:4b")
    )
    llm_timeout: int = field(
        default_factory=lambda: int(os.environ.get("WN_LLM_TIMEOUT", "300"))
    )

    # ── Logging ───────────────────────────────────────────────────────────────
    log_dir: Path = field(default_factory=_default_log_dir)

    # ── UI ────────────────────────────────────────────────────────────────────
    completed_reset_seconds: int = 4
    error_reset_seconds: int = 6

    # ── Derived sub-directories ───────────────────────────────────────────────
    @property
    def raw_dir(self) -> Path:
        return self.voice_notes_dir / "raw"

    @property
    def failed_audio_dir(self) -> Path:
        return self.voice_notes_dir / "failed_audio"

    @property
    def archive_dir(self) -> Path:
        return self.voice_notes_dir / "archive"


# ---------------------------------------------------------------------------
# Singleton
# ---------------------------------------------------------------------------

_active: Config | None = None


def init(cfg: Config | None = None) -> Config:
    """Set the active config.  Called once from cli.py before any other module runs."""
    global _active
    _active = cfg if cfg is not None else Config()
    return _active


def get() -> Config:
    """Return the active config, initialising with env-var defaults if not yet set."""
    if _active is None:
        init()
    return _active  # type: ignore[return-value]
