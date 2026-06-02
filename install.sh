#!/usr/bin/env bash
# =============================================================================
#  Whisper Note — Interactive Installer  (Ubuntu only)
#
#  Layout:
#    ┌──────────────────────────────────────┐  ← fixed header (never scrolls)
#    │  banner + live checklist             │
#    ├──────────────────────────────────────┤
#    │  command output scrolls here         │  ← scroll region
#    └──────────────────────────────────────┘
#
#  Each checklist item updates in-place:
#    [ ] pending  →  [▶] running…  →  [✓] done (Xs)
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; Y='\033[0;33m'; G='\033[0;32m'; GR='\033[90m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1m';    D='\033[2m'; X='\033[0m'

# ── Steps: name | time estimate ───────────────────────────────────────────────
STEP_NAMES=(
    "Install system packages"
    "Gather configuration"
    "Create virtual environment"
    "Install whisper-note from PyPI"
    "Write environment file"
    "Register systemd service"
    "Register desktop entry"
)
STEP_EST=(
    "~1-3 min"
    "user input"
    "~10 sec"
    "~2-5 min"
    "<1 sec"
    "~5 sec"
    "<1 sec"
)
STEP_STATE=( pending pending pending pending pending pending pending )
STEP_ACTUAL=( "" "" "" "" "" "" "" )

N_STEPS=${#STEP_NAMES[@]}

# ── Terminal layout ───────────────────────────────────────────────────────────
TERM_ROWS=$(tput lines)
TERM_COLS=$(tput cols)

#  Header block (fixed, above scroll region):
#    row 0  : blank
#    row 1  : ╔═══ banner ═══╗
#    row 2  : ║  title       ║
#    row 3  : ║  subtitle    ║
#    row 4  : ╚══════════════╝
#    row 5  : blank
#    row 6  : ┌─ checklist header
#    row 7  : │ step 1
#    row 8  : │ step 2  ...
#  row 7+N  : │ step N
# row 8+N   : └─ footer (total / elapsed)
# row 9+N   : blank separator
# row 10+N  : ▼ scroll region starts here

BANNER_ROWS=6       # rows 0-5
HDR_ROW=6           # "┌─ Installation progress" row
STEP_ROW_START=7    # first step row (0-indexed)
FOOTER_ROW=$(( STEP_ROW_START + N_STEPS ))
SEP_ROW=$(( FOOTER_ROW + 1 ))
SCROLL_START=$(( SEP_ROW + 1 ))   # first scrollable row

# Restore terminal on exit / Ctrl+C
_cleanup() {
    tput csr 0 $(( TERM_ROWS - 1 ))   # restore full scroll region
    tput cup $(( TERM_ROWS - 1 )) 0   # move to bottom
    echo
}
trap _cleanup EXIT INT TERM

# ── Draw the fixed header (called once) ──────────────────────────────────────
_draw_header() {
    tput cup 0 0; tput ed                    # go top, clear screen

    # Banner
    echo -e "${B}${W}"
    echo -e "  ╔══════════════════════════════════════════════════════════╗"
    echo -e "  ║   🎙  Whisper Note — Installer                           ║"
    echo -e "  ║       Voice-to-Markdown Note Taker  •  Ubuntu only      ║"
    echo -e "  ╚══════════════════════════════════════════════════════════╝${X}"
    echo

    # Checklist header
    printf "${D}  ┌── Installation progress"
    printf '%*s' $(( TERM_COLS - 28 )) ''
    printf "┐${X}\n"

    # Steps (all pending initially)
    for (( i=0; i<N_STEPS; i++ )); do
        _draw_step_line $i
    done

    # Footer line
    printf "${D}  └──────────────────────────────────────────────────────────┘${X}\n"

    # Separator before scroll region
    printf "${GR}  ── log output ─────────────────────────────────────────────${X}\n"

    # Set scroll region to rows below the header
    tput csr $SCROLL_START $(( TERM_ROWS - 1 ))

    # Park cursor at top of scroll region
    tput cup $SCROLL_START 0
}

# ── Draw one checklist line (called both initially and on update) ─────────────
_draw_step_line() {
    local i=$1
    local n=$(( i + 1 ))
    local name="${STEP_NAMES[$i]}"
    local est="${STEP_EST[$i]}"
    local actual="${STEP_ACTUAL[$i]}"

    case "${STEP_STATE[$i]}" in
        pending)
            printf "  ${D}│  [ ]  %-2s  %-34s  %-12s │${X}\n" \
                   "$n." "$name" "$est"
            ;;
        running)
            printf "  ${Y}│  [▶]  %-2s  %-34s  ⏱  running… │${X}\n" \
                   "$n." "$name"
            ;;
        done)
            printf "  ${G}│  [✓]  %-2s  %-34s  %-12s │${X}\n" \
                   "$n." "$name" "$actual"
            ;;
        failed)
            printf "  ${R}│  [✗]  %-2s  %-34s  FAILED      │${X}\n" \
                   "$n." "$name"
            ;;
    esac
}

# ── Update a single step line in-place ───────────────────────────────────────
_update_step() {
    local i=$1
    local state=$2
    local actual="${3:-}"

    STEP_STATE[$i]=$state
    STEP_ACTUAL[$i]=$actual

    tput sc                                       # save scroll-region cursor
    tput cup $(( STEP_ROW_START + i )) 0          # jump to checklist row
    tput el                                        # clear line
    _draw_step_line $i                            # redraw
    tput rc                                        # restore scroll-region cursor
}

# ── Update footer with elapsed time ──────────────────────────────────────────
_update_footer() {
    local done=0
    for s in "${STEP_STATE[@]}"; do [[ "$s" == "done" ]] && (( done++ )) || true; done
    local elapsed=$(( $(date +%s) - INSTALL_START ))
    local mins=$(( elapsed / 60 )); local secs=$(( elapsed % 60 ))

    tput sc
    tput cup $FOOTER_ROW 0; tput el
    printf "${D}  └── ${G}${done}/${N_STEPS} steps done${D}  •  elapsed: %dm %02ds%*s┘${X}\n" \
           $mins $secs $(( TERM_COLS - 46 )) ''
    tput rc
}

# ── Helpers ───────────────────────────────────────────────────────────────────
# Print a command in dim cyan, then run it (output goes to scroll region)
run() {
    echo -e "\n${D}${C}  \$ $*${X}"
    "$@"
}

ok()   { echo -e "${G}  ✓  ${1}${X}"; }
warn() { echo -e "${Y}  ⚠  ${1}${X}"; }
die()  { echo -e "\n${R}  ✗  ERROR: ${1}${X}" >&2; exit 1; }

ask() {
    echo -en "${W}  ${1}${X}  ${D}[default: ${Y}${2}${D}]${X}: "
    read -r _a; echo "${_a:-$2}"
}
ask_secret() {
    echo -en "${W}  ${1}${X}  ${D}[hidden — blank = skip]${X}: "
    read -rs _s; echo; echo "$_s"
}

# ── Time a step: mark running → run block → mark done ────────────────────────
# Usage:  timed_step INDEX  { commands... }
INSTALL_START=0   # set before loop
_step_start=0

begin_step() {
    local i=$(( $1 - 1 ))   # convert 1-based to 0-based
    _step_start=$(date +%s)
    _update_step $i running
    echo -e "\n${B}${W}  ── Step ${1}/${N_STEPS}: ${STEP_NAMES[$i]} ──────────────────${X}"
}

end_step() {
    local i=$(( $1 - 1 ))
    local elapsed=$(( $(date +%s) - _step_start ))
    local label
    if (( elapsed < 60 )); then
        label="${elapsed}s"
    else
        label="$(( elapsed/60 ))m $(( elapsed%60 ))s"
    fi
    _update_step $i done "$label"
    _update_footer
    ok "${STEP_NAMES[$i]} — done in ${label}"
}

# ═════════════════════════════════════════════════════════════════════════════
#  PREFLIGHT — Ubuntu check  (before drawing UI)
# ═════════════════════════════════════════════════════════════════════════════
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
OS_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
UBUNTU_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
if [[ "$OS_ID" != "ubuntu" && "$OS_LIKE" != *"ubuntu"* ]]; then
    echo -e "${R}  ✗  This installer requires Ubuntu (detected: ${OS_ID:-unknown}).${X}" >&2
    exit 1
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/whisper-note"
VENV_DIR="$INSTALL_DIR/venv"
CONF_DIR="$HOME/.config/whisper-note"
ENV_FILE="$CONF_DIR/env"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/whisper-note.service"

# ── Draw UI ───────────────────────────────────────────────────────────────────
_draw_header
echo -e "${G}  Ubuntu ${UBUNTU_VER} detected.${X}"

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 1 — System packages
# ═════════════════════════════════════════════════════════════════════════════
begin_step 1
INSTALL_START=$(date +%s)   # also used as global install start

echo -e "  ${D}Installing:${X}"
echo -e "    ${C}python3-venv python3-dev${X}          Python venv + headers"
echo -e "    ${C}python3-gi python3-gi-cairo${X}       GTK3 bindings (required for widget)"
echo -e "    ${C}gir1.2-gtk-3.0${X}                   GTK3 introspection data"
echo -e "    ${C}portaudio19-dev libsndfile1${X}       Audio capture libraries"
echo -e "    ${C}xdotool${X}                           X11 input utility"
echo -e "\n  ${Y}sudo is required — you may be prompted for your password.${X}"

run sudo apt-get update
run sudo apt-get install -y \
    python3-venv python3-dev \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1 \
    xdotool

end_step 1

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Configuration
# ═════════════════════════════════════════════════════════════════════════════
begin_step 2

echo -e "\n  ${W}── Speech-to-Text (Whisper) ──────────────────────────────────────${X}"
echo -e "  ${D}tiny=fastest/least-accurate  →  large-v3=slowest/most-accurate${X}"
WHISPER_MODEL=$(ask  "Whisper model  (tiny/base/small/medium/large-v3)" "base")
WHISPER_COMPUTE=$(ask "Compute type  (int8 is fastest on CPU)"          "int8")
VOICE_NOTES=$(ask    "Notes output directory"                           "$HOME/VoiceNotes")

echo -e "\n  ${W}── LLM Formatter ────────────────────────────────────────────────${X}"
echo -e "  ${D}Provider presets:${X}"
echo -e "    ${C}Ollama (local)${X}  URL: http://127.0.0.1:11434/v1   KEY: ollama"
echo -e "    ${C}OpenAI        ${X}  URL: https://api.openai.com/v1    KEY: sk-..."
echo -e "    ${C}Claude        ${X}  URL: https://api.anthropic.com/v1 KEY: sk-ant-..."
WN_LLM_URL=$(ask     "LLM API URL"               "http://127.0.0.1:11434/v1")
WN_LLM_KEY=$(ask_secret "LLM API key")
[[ -z "$WN_LLM_KEY" ]] && WN_LLM_KEY="ollama"
WN_LLM_MODEL=$(ask   "LLM model name"            "qwen3:4b")
WN_LLM_TIMEOUT=$(ask "LLM request timeout (sec)" "300")

echo
echo -e "  ${W}── Summary ──────────────────────────────────────────────────────${X}"
echo -e "    Whisper model   : ${G}${WHISPER_MODEL}${X} (${WHISPER_COMPUTE})"
echo -e "    Notes directory : ${G}${VOICE_NOTES}${X}"
echo -e "    LLM URL         : ${G}${WN_LLM_URL}${X}"
echo -e "    LLM model       : ${G}${WN_LLM_MODEL}${X}"
echo -e "    Install path    : ${G}${INSTALL_DIR}${X}"
echo
echo -en "  ${W}Proceed with installation?${X}  [${Y}Y/n${X}]: "
read -r _confirm
[[ "${_confirm,,}" == "n" ]] && { echo -e "\n  Aborted."; exit 0; }

end_step 2

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Virtual environment
# ═════════════════════════════════════════════════════════════════════════════
begin_step 3

echo -e "  ${D}Path    : ${VENV_DIR}${X}"
echo -e "  ${D}Note    : --system-site-packages lets the venv see python3-gi (GTK3)${X}"

run mkdir -p "$INSTALL_DIR"
run python3 -m venv --system-site-packages "$VENV_DIR"

echo -e "\n  ${D}Verifying GTK3 is visible inside the venv…${X}"
"$VENV_DIR/bin/python3" -c "
import gi; gi.require_version('Gtk','3.0')
from gi.repository import Gtk
print(f'  GTK3 OK — {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}')
"

end_step 3

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Install whisper-note
# ═════════════════════════════════════════════════════════════════════════════
begin_step 4

echo -e "  ${D}Downloading whisper-note and dependencies from PyPI.${X}"
echo -e "  ${D}This is the longest step — packages include faster-whisper (~300 MB model data on first run).${X}"

run "$VENV_DIR/bin/pip" install --upgrade pip
echo
run "$VENV_DIR/bin/pip" install whisper-note

VER=$("$VENV_DIR/bin/whisper-note" --version 2>/dev/null || echo "unknown")
echo -e "\n  Installed: ${G}${VER}${X}"

end_step 4

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Environment file
# ═════════════════════════════════════════════════════════════════════════════
begin_step 5

echo -e "  ${D}Path        : ${ENV_FILE}${X}"
echo -e "  ${D}Permissions : 600 (owner read/write only — protects your API key)${X}"

run mkdir -p "$CONF_DIR"

cat > "$ENV_FILE" << ENVEOF
# Whisper Note — environment configuration
# ─────────────────────────────────────────
# Change values:  whisper-note config set KEY=VALUE
# View values:    whisper-note config show
# Apply changes:  systemctl --user restart whisper-note

GDK_BACKEND=x11

# ── Whisper (speech-to-text) ──────────────────────────────────────────────────
WHISPER_MODEL=${WHISPER_MODEL}
WHISPER_COMPUTE_TYPE=${WHISPER_COMPUTE}

# ── Notes output ──────────────────────────────────────────────────────────────
VOICE_NOTES_DIR=${VOICE_NOTES}

# ── LLM formatter (OpenAI-compatible — Ollama / OpenAI / Claude) ──────────────
WN_LLM_URL=${WN_LLM_URL}
WN_LLM_KEY=${WN_LLM_KEY}
WN_LLM_MODEL=${WN_LLM_MODEL}
WN_LLM_TIMEOUT=${WN_LLM_TIMEOUT}
ENVEOF

chmod 600 "$ENV_FILE"

echo -e "\n  ${D}Written values:${X}"
grep -v "^#" "$ENV_FILE" | grep -v "^$" | grep -v "WN_LLM_KEY" | sed 's/^/    /'
echo -e "    WN_LLM_KEY=${D}<hidden>${X}"

end_step 5

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Systemd service
# ═════════════════════════════════════════════════════════════════════════════
begin_step 6

echo -e "  ${D}Service file  : ${SERVICE_FILE}${X}"
echo -e "  ${D}Env file      : ${ENV_FILE}${X}"
echo -e "  ${D}Autostart     : yes — starts on every graphical session login${X}"

run mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_FILE" << SVCEOF
[Unit]
Description=Whisper Note — voice-to-markdown note taker
Documentation=https://github.com/0xSh3ru/whisper-note
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/whisper-note --skip-checks
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
SVCEOF

run systemctl --user daemon-reload
run systemctl --user enable whisper-note
run systemctl --user start  whisper-note

sleep 1
echo -e "\n  ${D}Service status:${X}"
systemctl --user status whisper-note --no-pager | head -8 | sed 's/^/    /'

end_step 6

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 7 — Desktop entry
# ═════════════════════════════════════════════════════════════════════════════
begin_step 7

APPS_DIR="$HOME/.local/share/applications"
run mkdir -p "$APPS_DIR"

cat > "$APPS_DIR/whisper-note.desktop" << DESKEOF
[Desktop Entry]
Type=Application
Name=Whisper Note
Comment=Voice-to-markdown note taker — Hold Ctrl+Alt+Space to record
Exec=${VENV_DIR}/bin/whisper-note
Icon=audio-input-microphone
Categories=Utility;AudioVideo;
StartupNotify=false
NoDisplay=true
DESKEOF

update-desktop-database "$APPS_DIR" 2>/dev/null && \
    echo -e "  ${D}Desktop database updated.${X}" || true

end_step 7

# ═════════════════════════════════════════════════════════════════════════════
#  All done
# ═════════════════════════════════════════════════════════════════════════════
TOTAL_ELAPSED=$(( $(date +%s) - INSTALL_START ))
TOTAL_MIN=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SEC=$(( TOTAL_ELAPSED % 60 ))

echo
echo -e "${G}  ╔══════════════════════════════════════════════════════════╗"
echo -e "  ║                                                          ║"
echo -e "  ║   ✓  Installation complete in ${TOTAL_MIN}m ${TOTAL_SEC}s!                  ║"
echo -e "  ║                                                          ║"
echo -e "  ╚══════════════════════════════════════════════════════════╝${X}"
echo
echo -e "  The ${W}Whisper Note${X} widget is running in the ${W}top-right corner${X} of"
echo -e "  your screen and will start automatically on every login."
echo
echo -e "  ${W}How to use${X}"
echo -e "    ${Y}Hold${X}    Ctrl+Alt+Space  →  Recording starts  (widget turns red)"
echo -e "    ${Y}Release${X} any key         →  Transcribing…     (widget turns amber)"
echo -e "    ${Y}Done${X}                    →  Note saved!       (widget turns green)"
echo
echo -e "  ${W}Notes saved to${X}  ${C}${VOICE_NOTES}${X}"
echo
echo -e "  ${W}Service commands${X}"
echo -e "    ${C}systemctl --user start   whisper-note${X}"
echo -e "    ${C}systemctl --user stop    whisper-note${X}"
echo -e "    ${C}systemctl --user restart whisper-note${X}"
echo -e "    ${C}journalctl --user -u whisper-note -f${X}"
echo
echo -e "  ${W}Change config later${X}"
echo -e "    ${C}whisper-note config show${X}"
echo -e "    ${C}whisper-note config set WHISPER_MODEL=small${X}"
echo -e "    ${C}whisper-note config set WN_LLM_MODEL=gpt-4o-mini${X}"
echo
