"""whisper-note — voice-to-markdown note taker."""

from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("whisper-note")
except PackageNotFoundError:
    __version__ = "unknown"

__author__ = "Himangshu Pan"
__license__ = "MIT"
