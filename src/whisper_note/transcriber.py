"""
Whisper transcription — English only (language detection skipped).
Model is loaded once at startup via load_model() to avoid per-recording overhead.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from faster_whisper import WhisperModel

logger = logging.getLogger("whisper.transcriber")

_model: Optional[WhisperModel] = None


def load_model() -> None:
    """Load the Whisper model.  Must be called once before transcribe()."""
    global _model
    from whisper_note import config as cfg_mod
    cfg = cfg_mod.get()
    logger.info(f"Loading Whisper model: {cfg.whisper_model!r}  ({cfg.whisper_compute_type})")
    _model = WhisperModel(cfg.whisper_model, compute_type=cfg.whisper_compute_type)
    logger.info("Whisper model ready.")


def transcribe(wav_path: Path) -> str:
    """
    Transcribe a WAV file in English (language detection skipped).
    Returns the transcript as a plain string.
    Raises RuntimeError if load_model() was not called.
    Raises on transcription failure — caller handles artifact preservation.
    """
    if _model is None:
        raise RuntimeError(
            "Whisper model is not loaded. Call transcriber.load_model() at startup."
        )

    from whisper_note import config as cfg_mod
    beam_size = cfg_mod.get().whisper_beam_size

    logger.info(f"Transcribing: {wav_path.name}")
    segments, _ = _model.transcribe(
        str(wav_path),
        language="en",
        beam_size=beam_size,
    )

    transcript = " ".join(seg.text.strip() for seg in segments).strip()
    logger.info(f"Transcription complete — {len(transcript)} chars")
    logger.debug(f"Transcript: {transcript}")
    return transcript
