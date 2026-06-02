"""
GTK3 floating status window for Whisper Voice Note.

All public methods are thread-safe — call set_state() from any thread.
GTK updates are dispatched to the main thread via GLib.idle_add().

On Wayland + GNOME the window may not be kept above all windows by default.
Launch with GDK_BACKEND=x11 (XWayland) for reliable always-on-top behaviour:
    GDK_BACKEND=x11 python run.py
"""
import logging
import threading
from typing import Optional

logger = logging.getLogger("whisper.indicator")

# ---------------------------------------------------------------------------
# GTK availability guard — console fallback if GTK is absent
# ---------------------------------------------------------------------------
try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gtk, Gdk, GLib  # type: ignore
    _GTK_AVAILABLE = True
except Exception as _gtk_err:
    logger.warning(f"GTK3 unavailable ({_gtk_err}). Using console indicator.")
    _GTK_AVAILABLE = False

# ---------------------------------------------------------------------------
# State definitions
# ---------------------------------------------------------------------------
_STATES: dict[str, dict] = {
    "IDLE":       {"bg": "#3D3D3D", "bg_alt": None,      "fg": "#AAAAAA",
                   "label": "●  IDLE",          "flash": False},
    "RECORDING":  {"bg": "#CC0000", "bg_alt": None,      "fg": "#FFFFFF",
                   "label": "⬤  RECORDING",     "flash": False},
    "PROCESSING": {"bg": "#CC7700", "bg_alt": None,      "fg": "#FFFFFF",
                   "label": "◌  PROCESSING…",   "flash": False},
    "COMPLETED":  {"bg": "#007700", "bg_alt": None,      "fg": "#FFFFFF",
                   "label": "✓  COMPLETED",      "flash": False},
    "ERROR":      {"bg": "#FF0000", "bg_alt": "#660000", "fg": "#FFFFFF",
                   "label": "✗  ERROR",          "flash": True},
}

VALID_STATES = frozenset(_STATES)

# ---------------------------------------------------------------------------
# StatusIndicator
# ---------------------------------------------------------------------------

class StatusIndicator:
    """
    Small always-on-top status window.

    Usage:
        indicator = StatusIndicator()   # call from main thread before Gtk.main()
        indicator.set_state("RECORDING")           # safe from any thread
        indicator.set_state("COMPLETED", reset_after=4)  # auto-reset to IDLE
    """

    def __init__(self):
        self._current_state = "IDLE"
        self._flash_timer: Optional[int] = None
        self._reset_timer: Optional[int] = None
        self._flash_phase = False
        self._lock = threading.Lock()

        if not _GTK_AVAILABLE:
            return

        self._window = Gtk.Window()
        self._window.set_title("Whisper")
        self._window.set_decorated(False)
        self._window.set_keep_above(True)
        self._window.set_skip_taskbar_hint(True)
        self._window.set_skip_pager_hint(True)
        self._window.set_resizable(False)
        self._window.set_default_size(230, 52)
        self._window.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)

        # Position: top-right after realisation (geometry not yet known before)
        self._window.connect("realize", self._on_realize)
        self._window.connect("destroy", Gtk.main_quit)

        # Single CSS provider — reused for every state change
        self._css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            self._css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Label
        self._label = Gtk.Label()
        self._label.set_margin_start(18)
        self._label.set_margin_end(18)
        self._window.add(self._label)

        self._apply_state_internal("IDLE")
        self._window.show_all()

    # ── Public API ────────────────────────────────────────────────────────────

    def set_state(self, state: str, reset_after: Optional[int] = None) -> None:
        """
        Thread-safe state update.
        state:       one of IDLE / RECORDING / PROCESSING / COMPLETED / ERROR
        reset_after: if given, automatically revert to IDLE after this many seconds
        """
        if state not in VALID_STATES:
            logger.warning(f"Unknown indicator state: {state!r}")
            return

        if _GTK_AVAILABLE:
            GLib.idle_add(self._gtk_set_state, state, reset_after)
        else:
            label = _STATES[state]["label"]
            logger.info(f"[STATUS] {label}")

    def quit(self) -> None:
        """Trigger a clean shutdown of the GTK main loop."""
        if _GTK_AVAILABLE:
            GLib.idle_add(Gtk.main_quit)

    # ── GTK-thread internals ──────────────────────────────────────────────────

    def _gtk_set_state(self, state: str, reset_after: Optional[int]) -> bool:
        self._current_state = state
        self._cancel_timers()
        self._apply_state_internal(state)

        if _STATES[state]["flash"]:
            self._flash_phase = False
            self._flash_timer = GLib.timeout_add(450, self._tick_flash)

        if reset_after is not None:
            self._reset_timer = GLib.timeout_add_seconds(
                reset_after, self._do_reset_to_idle
            )

        return False  # idle_add runs once

    def _apply_state_internal(self, state: str, alt_bg: bool = False) -> None:
        s = _STATES[state]
        bg = s["bg_alt"] if (alt_bg and s["bg_alt"]) else s["bg"]
        fg = s["fg"]
        label_text = s["label"]

        css = f"""
        window {{
            background-color: {bg};
        }}
        label {{
            color: {fg};
            font-family: Monospace;
            font-weight: bold;
            font-size: 11pt;
        }}
        """
        self._css.load_from_data(css.encode())
        self._label.set_label(label_text)

    def _tick_flash(self) -> bool:
        if self._current_state != "ERROR":
            return False  # stop timer
        self._flash_phase = not self._flash_phase
        self._apply_state_internal("ERROR", alt_bg=self._flash_phase)
        return True  # continue

    def _do_reset_to_idle(self) -> bool:
        self._reset_timer = None
        self._gtk_set_state("IDLE", None)
        return False

    def _cancel_timers(self) -> None:
        if self._flash_timer is not None:
            GLib.source_remove(self._flash_timer)
            self._flash_timer = None
        if self._reset_timer is not None:
            GLib.source_remove(self._reset_timer)
            self._reset_timer = None

    def _on_realize(self, widget) -> None:
        display = Gdk.Display.get_default()
        if display is None:
            return
        monitor = display.get_primary_monitor()
        if monitor is None:
            return
        geom = monitor.get_geometry()
        w, h = self._window.get_size()
        self._window.move(geom.x + geom.width - w - 24, geom.y + 24)
