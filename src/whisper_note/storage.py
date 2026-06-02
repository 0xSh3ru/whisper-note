"""
File lifecycle management.

All writes use an atomic temp-then-rename pattern so a crash never leaves
a half-written note.  config.get() is called inside each function so the
singleton is always fully initialised before it is read.
"""
from __future__ import annotations

import logging
import os
import shutil
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

logger = logging.getLogger("whisper.storage")


def _cfg():
    from whisper_note import config as cfg_mod
    return cfg_mod.get()


# ---------------------------------------------------------------------------
# Directory management
# ---------------------------------------------------------------------------

def ensure_directories() -> None:
    """Create the full output directory tree if it does not yet exist."""
    cfg = _cfg()
    for d in (cfg.voice_notes_dir, cfg.raw_dir, cfg.failed_audio_dir, cfg.archive_dir):
        d.mkdir(parents=True, exist_ok=True)
    logger.debug(f"Directory tree ready under {cfg.voice_notes_dir}")


# ---------------------------------------------------------------------------
# File operations
# ---------------------------------------------------------------------------

def save_temp_wav(audio_np: np.ndarray) -> Path:
    """
    Write audio to a named temporary WAV file.
    The caller must either delete it (delete_temp) or move it
    (save_failed_audio) after processing.
    """
    cfg = _cfg()
    tmp = tempfile.NamedTemporaryFile(
        suffix=".wav",
        prefix="whisper_tmp_",
        delete=False,
    )
    sf.write(tmp.name, audio_np, cfg.sample_rate)
    path = Path(tmp.name)
    logger.debug(f"Temp WAV: {path}  ({path.stat().st_size} bytes)")
    return path


def save_raw_transcript(transcript: str, timestamp: str) -> Path:
    """Save raw transcript to raw/RAW_WHISPER_<timestamp>.txt (atomic write)."""
    final = _cfg().raw_dir / f"RAW_WHISPER_{timestamp}.txt"
    _atomic_write(final, transcript)
    logger.info(f"Raw transcript → {final}")
    return final


def save_markdown(content: str, timestamp: str) -> Path:
    """Save formatted markdown to WHISPER_<timestamp>.md (atomic write)."""
    final = _cfg().voice_notes_dir / f"WHISPER_{timestamp}.md"
    _atomic_write(final, content)
    logger.info(f"Markdown note → {final}")
    return final


def save_failed_audio(wav_path: Path, timestamp: str) -> Path:
    """Move a WAV that failed transcription to failed_audio/ for manual recovery."""
    dest = _cfg().failed_audio_dir / f"VOICE_{timestamp}.wav"
    shutil.move(str(wav_path), str(dest))
    logger.warning(f"Failed audio preserved → {dest}")
    return dest


def delete_temp(path: Path) -> None:
    """Remove a temporary file, logging but never raising on failure."""
    try:
        if path.exists():
            path.unlink()
            logger.debug(f"Deleted temp: {path}")
    except OSError as exc:
        logger.warning(f"Could not delete {path}: {exc}")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _atomic_write(dest: Path, content: str) -> None:
    """Write via sibling temp file + os.replace() so dest is never partial."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=dest.parent, prefix=".tmp_", suffix=dest.suffix)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_name, dest)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise
