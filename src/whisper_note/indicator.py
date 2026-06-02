"""
GTK3 floating status window for Whisper Note.

Solid dark card with a vivid state-coloured left accent bar.
Drag anywhere with left-click.

  ┌▌──────────────────────────────────┐
  │▌  🎙 WHISPER NOTE   Ctrl+Alt+Spc  │  ← header
  │▌  ───────────────────────────────  │
  │▌       ⬤   RECORDING              │  ← status
  │▌       Release any key to stop    │  ← hint
  │▌  ───────────────────────────────  │
  │▌              by Himangshu Pan    │  ← footer
  └▌──────────────────────────────────┘
   ↑ accent bar (colour = current state)

Thread-safe: set_state() may be called from any thread.
Drag with left-click to reposition.
"""
import logging
import threading
from typing import Optional

logger = logging.getLogger("whisper.indicator")

# ---------------------------------------------------------------------------
# GTK guard
# ---------------------------------------------------------------------------
try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gtk, Gdk, GLib  # type: ignore
    _GTK_AVAILABLE = True
except Exception as _err:
    logger.warning(f"GTK3 unavailable ({_err}). Using console indicator.")
    _GTK_AVAILABLE = False

# ---------------------------------------------------------------------------
# Theme — solid colours, no transparency
# ---------------------------------------------------------------------------
_BG        = "#1C1C2E"     # deep navy background (unchanged)
_BG_HDR    = "#14142A"     # slightly darker header strip
_SEP       = "#3A3A5C"     # separator line — lighter so it's visible
_TITLE_COL = "#C8C8FF"     # tool name — bright lavender, easy to read
_DEV_COL   = "#7070AA"     # dev credit — visible but secondary

# Per-state palette  — accent bar colour, icon, label, hint
# hint_markup replaces hint_col+hint for states that need styled text
_STATES: dict[str, dict] = {
    "IDLE": {
        "accent":       "#5555BB",
        "accent_alt":   None,
        "icon":         "●",
        "icon_col":     "#AAAAFF",
        "label":        "IDLE",
        "lbl_col":      "#DDDDFF",
        # Two-part markup: plain text + highlighted key combo + plain text
        "hint_markup": (
            "<span font='Sans 11' color='#8888BB'>Press &amp; hold  </span>"
            "<span font='Monospace Bold 12' color='#EEEEFF' "
            "background='#333366'> Ctrl+Alt+Space </span>"
            "<span font='Sans 11' color='#8888BB'>  to record</span>"
        ),
        "flash":        False,
    },
    "RECORDING": {
        "accent":       "#DD2222",
        "accent_alt":   None,
        "icon":         "⬤",
        "icon_col":     "#FF8888",
        "label":        "RECORDING",
        "lbl_col":      "#FFFFFF",
        "hint_markup":  "<span font='Sans Italic 12' color='#FFCCCC'>Release any key to stop recording</span>",
        "flash":        False,
    },
    "PROCESSING": {
        "accent":       "#CC7700",
        "accent_alt":   None,
        "icon":         "◌",
        "icon_col":     "#FFBB55",
        "label":        "PROCESSING",
        "lbl_col":      "#FFFFFF",
        "hint_markup":  "<span font='Sans Italic 12' color='#FFDDAA'>Transcribing audio…</span>",
        "flash":        False,
    },
    "COMPLETED": {
        "accent":       "#229944",
        "accent_alt":   None,
        "icon":         "✓",
        "icon_col":     "#66FF99",
        "label":        "COMPLETED",
        "lbl_col":      "#FFFFFF",
        "hint_markup":  "<span font='Sans Italic 12' color='#BBFFDD'>Note saved successfully!</span>",
        "flash":        False,
    },
    "ERROR": {
        "accent":       "#EE1111",
        "accent_alt":   "#660000",
        "icon":         "✗",
        "icon_col":     "#FF7777",
        "label":        "ERROR",
        "lbl_col":      "#FFFFFF",
        "hint_markup":  "<span font='Sans Italic 12' color='#FFBBBB'>Check log for details</span>",
        "flash":        True,
    },
}

VALID_STATES = frozenset(_STATES)

_DEVELOPER = "Himangshu Pan"
_HOTKEY    = "Ctrl+Alt+Space"

# Accent bar width (px)
_ACCENT_W  = 6
_WIN_W     = 420   # fixed width — prevents layout reflow between states
_WIN_H     = 162   # fixed height

# ---------------------------------------------------------------------------
# StatusIndicator
# ---------------------------------------------------------------------------

class StatusIndicator:
    def __init__(self):
        self._current_state = "IDLE"
        self._flash_timer:  Optional[int] = None
        self._reset_timer:  Optional[int] = None
        self._flash_phase   = False
        self._lock          = threading.Lock()

        if not _GTK_AVAILABLE:
            return

        # ── Window ───────────────────────────────────────────────────────────
        self._window = Gtk.Window()
        self._window.set_title("Whisper Note")
        self._window.set_decorated(False)
        self._window.set_keep_above(True)
        self._window.set_skip_taskbar_hint(True)
        self._window.set_skip_pager_hint(True)
        self._window.set_resizable(False)
        # UTILITY allows the WM to honour move requests; NOTIFICATION does not
        self._window.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        self._window.set_default_size(_WIN_W, _WIN_H)
        self._window.set_size_request(_WIN_W, _WIN_H)
        self._window.connect("realize", self._on_realize)
        self._window.connect("destroy", Gtk.main_quit)

        # Drag state
        self._dragging      = False
        self._drag_offset_x = 0
        self._drag_offset_y = 0

        # ── CSS ──────────────────────────────────────────────────────────────
        self._css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(
            self._window.get_screen(),
            self._css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # ── Root HBox: accent bar | content ──────────────────────────────────
        root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)

        # Left accent bar (EventBox so we can colour it via CSS name)
        self._accent_bar = Gtk.EventBox()
        self._accent_bar.set_name("accent")
        self._accent_bar.set_size_request(_ACCENT_W, -1)
        root.pack_start(self._accent_bar, False, False, 0)

        # Content column
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.pack_start(content, True, True, 0)

        # — Header area (slightly darker bg via name)
        hdr_box = Gtk.EventBox()
        hdr_box.set_name("header")
        hdr_inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        hdr_inner.set_margin_top(12)
        hdr_inner.set_margin_bottom(10)
        hdr_inner.set_margin_start(14)
        hdr_inner.set_margin_end(14)
        hdr_box.add(hdr_inner)
        self._title_lbl  = Gtk.Label()
        self._hotkey_lbl = Gtk.Label()
        self._title_lbl.set_halign(Gtk.Align.START)
        self._title_lbl.set_hexpand(True)
        self._hotkey_lbl.set_halign(Gtk.Align.END)
        hdr_inner.pack_start(self._title_lbl,  True,  True,  0)
        hdr_inner.pack_start(self._hotkey_lbl, False, False, 0)
        content.pack_start(hdr_box, False, False, 0)

        content.pack_start(self._sep(), False, False, 0)

        # — Body
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        body.set_margin_top(14)
        body.set_margin_bottom(12)
        body.set_margin_start(14)
        body.set_margin_end(14)

        # Status row: large icon + bold label
        status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self._icon_lbl   = Gtk.Label()
        self._status_lbl = Gtk.Label()
        self._icon_lbl.set_halign(Gtk.Align.CENTER)
        self._status_lbl.set_halign(Gtk.Align.START)
        status_row.pack_start(self._icon_lbl,   False, False, 0)
        status_row.pack_start(self._status_lbl,  True,  True,  0)
        body.pack_start(status_row, False, False, 0)

        # Hint (indented under icon)
        self._hint_lbl = Gtk.Label()
        self._hint_lbl.set_halign(Gtk.Align.START)
        self._hint_lbl.set_margin_start(46)
        self._hint_lbl.set_margin_top(4)
        body.pack_start(self._hint_lbl, False, False, 0)

        content.pack_start(body, True, True, 0)

        content.pack_start(self._sep(), False, False, 0)

        # — Footer: dev credit
        ftr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        ftr.set_margin_top(7)
        ftr.set_margin_bottom(8)
        ftr.set_margin_start(14)
        ftr.set_margin_end(14)
        self._dev_lbl = Gtk.Label()
        self._dev_lbl.set_halign(Gtk.Align.END)
        self._dev_lbl.set_hexpand(True)
        ftr.pack_start(self._dev_lbl, True, True, 0)
        content.pack_start(ftr, False, False, 0)

        self._window.add(root)

        # ── Drag-to-move ─────────────────────────────────────────────────────
        # Manual tracking is more reliable than begin_move_drag under XWayland.
        # We attach to the window AND every EventBox so button-press is caught
        # regardless of which child widget the cursor is over.
        _drag_mask = (
            Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.BUTTON1_MOTION_MASK
        )
        for widget in (self._window, self._accent_bar, hdr_box):
            widget.add_events(_drag_mask)
            widget.connect("button-press-event",   self._on_drag_start)
            widget.connect("button-release-event", self._on_drag_end)
            widget.connect("motion-notify-event",  self._on_drag_motion)

        self._apply_state_internal("IDLE")
        self._window.show_all()

    # ── Public API ────────────────────────────────────────────────────────────

    def set_state(self, state: str, reset_after: Optional[int] = None) -> None:
        if state not in VALID_STATES:
            logger.warning(f"Unknown indicator state: {state!r}")
            return
        if _GTK_AVAILABLE:
            GLib.idle_add(self._gtk_set_state, state, reset_after)
        else:
            s = _STATES[state]
            logger.info(f"[STATUS] {s['icon']}  {s['label']}  —  {s['hint']}")

    def quit(self) -> None:
        if _GTK_AVAILABLE:
            GLib.idle_add(Gtk.main_quit)

    # ── Drag-to-move ──────────────────────────────────────────────────────────

    def _on_drag_start(self, _, event) -> bool:
        if event.button == 1:
            self._dragging = True
            wx, wy = self._window.get_position()
            self._drag_offset_x = int(event.x_root) - wx
            self._drag_offset_y = int(event.y_root) - wy
        return False   # let event propagate so children still work

    def _on_drag_end(self, _, event) -> bool:
        if event.button == 1:
            self._dragging = False
        return False

    def _on_drag_motion(self, _, event) -> bool:
        if self._dragging:
            self._window.move(
                int(event.x_root) - self._drag_offset_x,
                int(event.y_root) - self._drag_offset_y,
            )
        return False

    # ── GTK internals ────────────────────────────────────────────────────────

    def _gtk_set_state(self, state: str, reset_after: Optional[int]) -> bool:
        self._current_state = state
        self._cancel_timers()
        self._apply_state_internal(state)

        if _STATES[state]["flash"]:
            self._flash_phase = False
            self._flash_timer = GLib.timeout_add(500, self._tick_flash)

        if reset_after is not None:
            self._reset_timer = GLib.timeout_add_seconds(
                reset_after, self._do_reset_to_idle
            )
        return False

    def _apply_state_internal(self, state: str, alt: bool = False) -> None:
        s      = _STATES[state]
        accent = s["accent_alt"] if (alt and s["accent_alt"]) else s["accent"]

        self._css.load_from_data(f"""
            window  {{ background-color: {_BG}; }}
            #accent {{ background-color: {accent}; }}
            #header {{ background-color: {_BG_HDR}; }}
            separator {{ background-color: {_SEP}; min-height: 1px; }}
        """.encode())

        self._title_lbl.set_markup(
            f"<span font='Monospace Bold 13' color='{_TITLE_COL}'>🎙  WHISPER NOTE</span>"
        )
        # Header right: subtle drag affordance instead of tiny hotkey text
        self._hotkey_lbl.set_markup(
            "<span font='Sans 9' color='#3A3A5A'>⠿ drag</span>"
        )
        icon_col = s["icon_col"]
        icon_chr = s["icon"]
        lbl_col  = s["lbl_col"]
        lbl_text = s["label"]

        self._icon_lbl.set_markup(
            f"<span font='Monospace 32' color='{icon_col}'>{icon_chr}</span>"
        )
        self._status_lbl.set_markup(
            f"<span font='Sans Bold 19' color='{lbl_col}'>{lbl_text}</span>"
        )
        self._hint_lbl.set_markup(s["hint_markup"])
        dev_col = _DEV_COL
        dev_name = _DEVELOPER
        self._dev_lbl.set_markup(
            f"<span font='Sans 10' color='{dev_col}'>by {dev_name}</span>"
        )

    def _tick_flash(self) -> bool:
        if self._current_state != "ERROR":
            return False
        self._flash_phase = not self._flash_phase
        self._apply_state_internal("ERROR", alt=self._flash_phase)
        return True

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

    def _on_realize(self, _) -> None:
        display = Gdk.Display.get_default()
        if display is None:
            return
        monitor = display.get_primary_monitor()
        if monitor is None:
            return
        geom = monitor.get_geometry()
        w, _ = self._window.get_size()
        self._window.move(geom.x + geom.width - w - 24, geom.y + 24)

    @staticmethod
    def _sep():
        return Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
