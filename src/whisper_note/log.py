"""Session logging — one timestamped log file per run."""
from __future__ import annotations

import logging
import tempfile
from pathlib import Path


def setup(session_ts: str) -> tuple[logging.Logger, Path]:
    """
    Configure file + console logging.
    Preferred log directory comes from config; falls back gracefully.
    Returns (root whisper logger, resolved log file path).
    """
    from whisper_note import config as cfg_mod
    log_dir = _resolve_log_dir(cfg_mod.get().log_dir)
    log_file = log_dir / f"whisper_{session_ts}.log"

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)-8s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    logger = logging.getLogger("whisper")
    logger.setLevel(logging.DEBUG)

    if not logger.handlers:
        fh = logging.FileHandler(log_file, encoding="utf-8")
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(fmt)
        logger.addHandler(fh)

        ch = logging.StreamHandler()
        ch.setLevel(logging.INFO)
        ch.setFormatter(fmt)
        logger.addHandler(ch)

    return logger, log_file


def _resolve_log_dir(preferred: Path) -> Path:
    """Try preferred, fall back to ~/whisper-logs, then system temp."""
    fallback = Path.home() / "whisper-logs"
    for candidate in (preferred, fallback):
        try:
            candidate.mkdir(parents=True, exist_ok=True)
            probe = candidate / ".write_probe"
            probe.touch()
            probe.unlink()
            return candidate
        except (PermissionError, OSError):
            continue
    return Path(tempfile.gettempdir())
