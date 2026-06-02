"""Thread-safe audio capture via sounddevice."""
from __future__ import annotations

import logging
import threading
from typing import Optional

import numpy as np
import sounddevice as sd

logger = logging.getLogger("whisper.recorder")


def _sample_rate() -> int:
    from whisper_note import config as cfg_mod
    return cfg_mod.get().sample_rate


class Recorder:
    def __init__(self):
        self._lock = threading.Lock()
        self._chunks: list[np.ndarray] = []
        self._stream: Optional[sd.InputStream] = None
        self._active = False

    @property
    def is_active(self) -> bool:
        with self._lock:
            return self._active

    def start(self) -> None:
        with self._lock:
            if self._active:
                return
            self._chunks = []
            self._active = True

        self._stream = sd.InputStream(
            samplerate=_sample_rate(),
            channels=1,
            dtype="float32",
            callback=self._callback,
        )
        self._stream.start()
        logger.info("Recording started.")

    def stop(self) -> Optional[np.ndarray]:
        """Stop capture and return concatenated audio, or None if empty."""
        with self._lock:
            if not self._active:
                return None
            self._active = False
            chunks = list(self._chunks)
            self._chunks = []

        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception as exc:
                logger.warning(f"Error closing audio stream: {exc}")
            finally:
                self._stream = None

        logger.info(f"Recording stopped — {len(chunks)} chunk(s).")

        if not chunks:
            return None
        return np.concatenate(chunks, axis=0)

    def _callback(
        self,
        indata: np.ndarray,
        frames: int,
        time_info,
        status: sd.CallbackFlags,
    ) -> None:
        if status:
            logger.warning(f"Stream status: {status}")
        with self._lock:
            if self._active:
                self._chunks.append(indata.copy())
