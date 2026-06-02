"""
Application orchestration.

Thread layout:
  Main thread   — GTK main loop (blocks until quit)
  pynput thread — keyboard listener (daemon, started before Gtk.main)
  Worker thread — one per recording, runs the full processing pipeline
"""
from __future__ import annotations

import logging
import os
import threading
import traceback
from datetime import datetime

from pynput import keyboard as kb

from whisper_note import formatter as formatter_mod
from whisper_note import storage
from whisper_note import transcriber as transcriber_mod
from whisper_note.formatter import format_transcript
from whisper_note.indicator import StatusIndicator, _GTK_AVAILABLE
from whisper_note.log import setup as setup_logging
from whisper_note.recorder import Recorder

if _GTK_AVAILABLE:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk  # type: ignore

SESSION_TS = datetime.now().strftime("%Y%m%d_%H%M%S")
_root_logger, SESSION_LOG = setup_logging(SESSION_TS)
logger = logging.getLogger("whisper.main")

# Singletons
indicator = StatusIndicator()
recorder  = Recorder()

# Keyboard state — only mutated from the pynput thread
_ctrl_held = False
_alt_held  = False


# ---------------------------------------------------------------------------
# Processing pipeline
# ---------------------------------------------------------------------------

def _run_pipeline(audio_np) -> None:
    """Runs in a daemon thread — full lifecycle for one recording."""
    from whisper_note import config as cfg_mod
    cfg     = cfg_mod.get()
    note_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    tmp_wav = None

    try:
        tmp_wav = storage.save_temp_wav(audio_np)

        try:
            transcript = transcriber_mod.transcribe(tmp_wav)
        except Exception:
            logger.error("Whisper transcription failed:\n" + traceback.format_exc())
            storage.save_failed_audio(tmp_wav, note_ts)
            tmp_wav = None
            indicator.set_state("ERROR", reset_after=cfg.error_reset_seconds)
            return

        if not transcript.strip():
            logger.warning("Empty transcript — nothing to save.")
            indicator.set_state("IDLE")
            return

        storage.save_raw_transcript(transcript, note_ts)
        markdown = format_transcript(transcript, note_ts)
        storage.save_markdown(markdown, note_ts)

        indicator.set_state("COMPLETED", reset_after=cfg.completed_reset_seconds)
        logger.info(f"Note {note_ts} complete.")

    except Exception:
        logger.error("Unexpected pipeline error:\n" + traceback.format_exc())
        indicator.set_state("ERROR", reset_after=cfg.error_reset_seconds)
    finally:
        if tmp_wav is not None:
            storage.delete_temp(tmp_wav)


# ---------------------------------------------------------------------------
# Recording control (called from the pynput thread)
# ---------------------------------------------------------------------------

def _start_recording() -> None:
    if recorder.is_active:
        return
    recorder.start()
    indicator.set_state("RECORDING")


def _stop_and_process() -> None:
    if not recorder.is_active:
        return

    audio_np = recorder.stop()

    if audio_np is None or audio_np.size == 0:
        logger.warning("Empty recording — discarded.")
        indicator.set_state("IDLE")
        return

    from whisper_note import config as cfg_mod
    duration = audio_np.shape[0] / cfg_mod.get().sample_rate
    logger.info(f"Captured {duration:.1f}s of audio.")

    indicator.set_state("PROCESSING")
    threading.Thread(
        target=_run_pipeline,
        args=(audio_np,),
        name="whisper-pipeline",
        daemon=True,
    ).start()


# ---------------------------------------------------------------------------
# Keyboard listener  —  Hold Ctrl+Alt+Space to record, release to process
# ---------------------------------------------------------------------------

def _on_press(key) -> None:
    global _ctrl_held, _alt_held
    if key in (kb.Key.ctrl_l, kb.Key.ctrl_r):
        _ctrl_held = True
    elif key in (kb.Key.alt_l, kb.Key.alt_r):
        _alt_held = True
    elif key == kb.Key.space and _ctrl_held and _alt_held:
        _start_recording()


def _on_release(key):
    global _ctrl_held, _alt_held
    if key in (kb.Key.ctrl_l, kb.Key.ctrl_r):
        _ctrl_held = False
        if recorder.is_active:
            _stop_and_process()
    elif key in (kb.Key.alt_l, kb.Key.alt_r):
        _alt_held = False
        if recorder.is_active:
            _stop_and_process()
    elif key == kb.Key.space:
        if recorder.is_active:
            _stop_and_process()
    elif key == kb.Key.esc:
        logger.info("ESC — shutting down.")
        indicator.quit()
        if not _GTK_AVAILABLE:
            os._exit(0)
        return False  # stops pynput listener


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    from whisper_note import config as cfg_mod
    cfg = cfg_mod.get()

    logger.info("=" * 60)
    logger.info("whisper-note starting")
    logger.info(f"Session : {SESSION_TS}")
    logger.info(f"Log     : {SESSION_LOG}")
    logger.info(f"Notes   : {cfg.voice_notes_dir}")
    logger.info(f"Model   : {cfg.whisper_model}  ({cfg.whisper_compute_type})")
    if cfg.llm_backend == "local":
        logger.info(f"LLM     : local GGUF  →  {cfg.llm_gguf_path}")
    else:
        logger.info(f"LLM     : {cfg.llm_model}  →  {cfg.llm_url}  (http)")

    storage.ensure_directories()
    transcriber_mod.load_model()
    formatter_mod.load_model()  # no-op unless the local backend is selected

    logger.info("Ready — Hold Ctrl+Alt+Space to record | Release to process | Esc to quit")
    logger.info("=" * 60)

    listener = kb.Listener(on_press=_on_press, on_release=_on_release)
    listener.daemon = True
    listener.start()

    if _GTK_AVAILABLE:
        Gtk.main()
    else:
        listener.join()

    logger.info("whisper-note stopped.")
