#!/usr/bin/env bash
# =============================================================================
#  Whisper Note — Interactive Installer  (Ubuntu only)
#
#  Flow:
#    Phase 1 — whiptail wizard (friendly dialogs, collects all config)
#    Phase 2 — installation   (fixed header + live scrolling log below it)
#
#  Fixed header layout during Phase 2:
#    ┌──────────────────────────────────────────────────┐
#    │  banner                                          │  ← never scrolls
#    ├──────────────────────────────────────────────────┤
#    │  [✓] step 1  │  [▶] step 2  │  [ ] step 3 ...  │
#    └──────────────────────────────────────────────────┘
#    ── log output ─────────────────────────────────────
#    [apt / pip / systemctl output scrolls here]
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; Y='\033[0;33m'; G='\033[0;32m'; GR='\033[90m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1m'; D='\033[2m'; X='\033[0m'

# ── whiptail theme (dark, cyan accent) ───────────────────────────────────────
export NEWT_COLORS='
root=white,black
window=white,black
border=cyan,black
title=brightcyan,black
button=black,cyan
actbutton=black,white
checkbox=white,black
actcheckbox=black,cyan
entry=brightwhite,black
label=white,black
listbox=white,black
actlistbox=black,cyan
textbox=white,black
acttextbox=black,cyan
sellistbox=black,cyan
actsellistbox=black,cyan
helpline=black,cyan
roottext=brightwhite,black
'

# ── Utility ───────────────────────────────────────────────────────────────────
die()  { echo -e "\n${R}  ✗  ERROR: ${1}${X}" >&2; exit 1; }
run()  { echo -e "\n${D}${C}  \$ $*${X}"; "$@"; }
ok()   { echo -e "${G}  ✓  ${1}${X}"; }
info() { echo -e "${C}  ▶  ${1}${X}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/whisper-note"
VENV_DIR="$INSTALL_DIR/venv"
CONF_DIR="$HOME/.config/whisper-note"
ENV_FILE="$CONF_DIR/env"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/whisper-note.service"

# ── Ubuntu guard ──────────────────────────────────────────────────────────────
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
OS_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
UBUNTU_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
[[ "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"ubuntu"* ]] || \
    die "This installer requires Ubuntu (detected: ${OS_ID:-unknown})."

# =============================================================================
#  PHASE 1 — Configuration wizard  (whiptail dialogs)
# =============================================================================

_wt() { whiptail --backtitle "  🎙  Whisper Note Installer  •  Ubuntu ${UBUNTU_VER}" "$@"; }

# ── Welcome ───────────────────────────────────────────────────────────────────
_wt --title "  Welcome  " --msgbox \
"Welcome to the Whisper Note installer!

This wizard will:

  1.  Install required system packages  (apt)
  2.  Ask a few configuration questions
  3.  Create a dedicated Python environment
  4.  Install whisper-note from PyPI
  5.  Write your settings to a secure env file
  6.  Register and start a systemd user service
  7.  Register a desktop entry

Your configuration can be changed any time with:
  whisper-note config set KEY=VALUE

Press Enter to continue." 22 65

# ── Whisper model ─────────────────────────────────────────────────────────────
WHISPER_MODEL=$( _wt --title "  Speech-to-Text Model  " \
    --menu "\nChoose the Whisper model for local transcription.\n\nSmaller = faster,  Larger = more accurate.\nThe selected model downloads automatically on first use." \
    20 68 5 \
    "base"     "74 MB  ·  Fast & good accuracy     ← Recommended" \
    "tiny"     "39 MB  ·  Fastest (testing / weak hardware)" \
    "small"    "244 MB ·  Better accuracy" \
    "medium"   "769 MB ·  High accuracy" \
    "large-v3" "1.5 GB ·  Best accuracy (needs good hardware)" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# ── Compute type ──────────────────────────────────────────────────────────────
WHISPER_COMPUTE=$( _wt --title "  Compute Type  " \
    --menu "\nChoose inference precision.\n\n'int8' is fastest on CPU and recommended for most users.\nUse 'float16' only if you have a CUDA GPU." \
    15 62 3 \
    "int8"    "Fastest  ·  CPU optimised  ← Recommended" \
    "float16" "Faster   ·  GPU (CUDA) required" \
    "float32" "Accurate ·  Most compatible, slowest" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# ── Notes directory ───────────────────────────────────────────────────────────
VOICE_NOTES=$( _wt --title "  Notes Directory  " \
    --inputbox "\nWhere should whisper-note save your markdown notes?\n\nThe directory will be created if it does not exist." \
    12 62 "$HOME/VoiceNotes" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# ── LLM provider ─────────────────────────────────────────────────────────────
PROVIDER=$( _wt --title "  LLM Formatter  " \
    --menu "\nChoose the AI provider for formatting transcripts into markdown.\n\nOllama runs locally (no API key needed).\nOpenAI and Claude require an API key." \
    16 65 4 \
    "ollama" "Local Ollama  (no key needed — runs on your machine)" \
    "openai" "OpenAI API    (requires sk-... key)" \
    "claude" "Anthropic Claude  (requires sk-ant-... key)" \
    "custom" "Custom OpenAI-compatible endpoint" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# Pre-fill URL / key / model defaults based on provider choice
case "$PROVIDER" in
    ollama)
        _DEFAULT_URL="http://127.0.0.1:11434/v1"
        _DEFAULT_KEY="ollama"
        _DEFAULT_MODEL="qwen3:4b"
        ;;
    openai)
        _DEFAULT_URL="https://api.openai.com/v1"
        _DEFAULT_KEY=""
        _DEFAULT_MODEL="gpt-4o-mini"
        ;;
    claude)
        _DEFAULT_URL="https://api.anthropic.com/v1"
        _DEFAULT_KEY=""
        _DEFAULT_MODEL="claude-haiku-4-5-20251001"
        ;;
    custom)
        _DEFAULT_URL="http://localhost:11434/v1"
        _DEFAULT_KEY=""
        _DEFAULT_MODEL=""
        ;;
esac

# ── LLM model name ────────────────────────────────────────────────────────────
WN_LLM_MODEL=$( _wt --title "  LLM Model Name  " \
    --inputbox "\nEnter the model name to use for markdown formatting.\n\nExamples:\n  Ollama  →  qwen3:4b  /  llama3.2  /  mistral\n  OpenAI  →  gpt-4o-mini  /  gpt-4o\n  Claude  →  claude-haiku-4-5-20251001" \
    15 65 "$_DEFAULT_MODEL" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# ── LLM API key ───────────────────────────────────────────────────────────────
if [[ "$PROVIDER" == "ollama" ]]; then
    WN_LLM_KEY="ollama"
else
    WN_LLM_KEY=$( _wt --title "  LLM API Key  " \
        --passwordbox "\nEnter your API key.\n\nThis will be stored in:\n  ${ENV_FILE}\nwith permissions 600 (readable only by you)." \
        13 65 \
        3>&1 1>&2 2>&3 ) || die "Installation cancelled."
    [[ -n "$WN_LLM_KEY" ]] || die "API key is required for ${PROVIDER}."
fi

# ── LLM URL (shown for custom; fixed for presets) ─────────────────────────────
if [[ "$PROVIDER" == "custom" ]]; then
    WN_LLM_URL=$( _wt --title "  LLM API URL  " \
        --inputbox "\nEnter the base URL of the OpenAI-compatible API endpoint.\n\nExample: http://127.0.0.1:11434/v1" \
        11 65 "$_DEFAULT_URL" \
        3>&1 1>&2 2>&3 ) || die "Installation cancelled."
else
    WN_LLM_URL="$_DEFAULT_URL"
fi

# ── Request timeout ───────────────────────────────────────────────────────────
WN_LLM_TIMEOUT=$( _wt --title "  LLM Request Timeout  " \
    --inputbox "\nMaximum seconds to wait for a formatting response.\n\nIncrease this if using Ollama on CPU (can be slow).\nCloud providers (OpenAI, Claude) usually finish in <10s." \
    12 65 "300" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# ── Confirm ───────────────────────────────────────────────────────────────────
_wt --title "  Confirm Installation  " --yesno \
"Ready to install with these settings:

  Whisper model   :  ${WHISPER_MODEL}  (${WHISPER_COMPUTE})
  Notes directory :  ${VOICE_NOTES}

  LLM provider    :  ${PROVIDER}
  LLM URL         :  ${WN_LLM_URL}
  LLM model       :  ${WN_LLM_MODEL}
  LLM timeout     :  ${WN_LLM_TIMEOUT}s

  Install path    :  ${INSTALL_DIR}

Proceed with installation?" \
20 65 || { echo -e "\n  Aborted."; exit 0; }

# =============================================================================
#  PHASE 2 — Installation  (fixed header + scrolling log)
# =============================================================================

# ── Step definitions for the progress checklist ───────────────────────────────
STEP_NAMES=(
    "Install system packages"
    "Create Python virtual environment"
    "Install whisper-note from PyPI"
    "Write environment file"
    "Register systemd service"
    "Register desktop entry"
)
STEP_EST=( "~1-3 min" "~10 sec" "~2-5 min" "<1 sec" "~5 sec" "<1 sec" )
STEP_STATE=( pending pending pending pending pending pending )
STEP_ACTUAL=( "" "" "" "" "" "" )
N_STEPS=${#STEP_NAMES[@]}

TERM_ROWS=$(tput lines)
TERM_COLS=$(tput cols)

# Fixed area rows:
#   0      : blank
#   1-4    : banner (4 rows)
#   5      : blank
#   6      : checklist header
#   7..7+N : checklist items
#   7+N    : checklist footer
#   8+N    : separator
#   9+N    : scroll region starts

BANNER_ROWS=6
HDR_ROW=6
STEP_ROW_START=7
FOOTER_ROW=$(( STEP_ROW_START + N_STEPS ))
SEP_ROW=$(( FOOTER_ROW + 1 ))
SCROLL_START=$(( SEP_ROW + 1 ))
INSTALL_START=$(date +%s)

# Restore terminal cleanly on any exit
_cleanup() {
    tput csr 0 $(( $(tput lines) - 1 )) 2>/dev/null || true
    tput cup $(( $(tput lines) - 2 )) 0 2>/dev/null || true
    echo
}
trap _cleanup EXIT INT TERM

# ── Draw one checklist line ───────────────────────────────────────────────────
_draw_step_line() {
    local i=$1
    local n=$(( i + 1 ))
    local name="${STEP_NAMES[$i]}"
    local est="${STEP_EST[$i]}"
    local actual="${STEP_ACTUAL[$i]}"
    local pad=$(( TERM_COLS - 52 ))
    [[ $pad -lt 0 ]] && pad=0

    case "${STEP_STATE[$i]}" in
        pending)
            printf "  ${D}│  [ ]  %s. %-32s  %-10s%*s│${X}\n" \
                   "$n" "$name" "$est" $pad ''
            ;;
        running)
            printf "  ${Y}│  [▶]  %s. %-32s  %-10s%*s│${X}\n" \
                   "$n" "$name" "⏱ running…" $pad ''
            ;;
        done)
            printf "  ${G}│  [✓]  %s. %-32s  %-10s%*s│${X}\n" \
                   "$n" "$name" "$actual" $pad ''
            ;;
        failed)
            printf "  ${R}│  [✗]  %s. %-32s  %-10s%*s│${X}\n" \
                   "$n" "$name" "FAILED" $pad ''
            ;;
    esac
}

# ── Draw the whole fixed header (once at start) ───────────────────────────────
_draw_header() {
    tput cup 0 0; tput ed

    echo -e "${B}${W}"
    echo -e "  ╔══════════════════════════════════════════════════════════╗"
    echo -e "  ║   🎙  Whisper Note — Installing…                         ║"
    echo -e "  ║       Hold Ctrl+Alt+Space to record after install        ║"
    echo -e "  ╚══════════════════════════════════════════════════════════╝${X}"
    echo

    local pad=$(( TERM_COLS - 56 ))
    [[ $pad -lt 0 ]] && pad=0
    printf "${D}  ┌─── Installation steps%*s┐${X}\n" $pad ''
    for (( i=0; i<N_STEPS; i++ )); do _draw_step_line $i; done
    printf "${D}  └─── 0/%s done  •  starting…%*s┘${X}\n" \
           "$N_STEPS" $(( pad - 10 )) ''
    printf "${GR}  ── log output %s${X}\n" \
           "$(printf '─%.0s' $(seq 1 $(( TERM_COLS - 18 ))))"

    tput csr $SCROLL_START $(( TERM_ROWS - 1 ))
    tput cup $SCROLL_START 0
}

# ── Update one checklist line in-place ───────────────────────────────────────
_update_step() {
    local i=$1 state=$2 actual="${3:-}"
    STEP_STATE[$i]=$state
    STEP_ACTUAL[$i]=$actual
    tput sc
    tput cup $(( STEP_ROW_START + i )) 0; tput el
    _draw_step_line $i
    tput rc
}

# ── Update footer with current progress + elapsed time ────────────────────────
_update_footer() {
    local done=0
    for s in "${STEP_STATE[@]}"; do [[ "$s" == "done" ]] && (( done++ )) || true; done
    local elapsed=$(( $(date +%s) - INSTALL_START ))
    local m=$(( elapsed/60 )) s=$(( elapsed%60 ))
    local pad=$(( TERM_COLS - 56 ))
    [[ $pad -lt 0 ]] && pad=0
    tput sc
    tput cup $FOOTER_ROW 0; tput el
    printf "${D}  └─── ${G}%s/%s done${D}  •  elapsed: %dm %02ds%*s┘${X}\n" \
           "$done" "$N_STEPS" "$m" "$s" $pad ''
    tput rc
}

# ── Step lifecycle helpers ────────────────────────────────────────────────────
_step_start_ts=0

begin_step() {
    local i=$(( $1 - 1 ))
    _step_start_ts=$(date +%s)
    _update_step $i running
    echo -e "\n${B}${W}  ── Step ${1}/${N_STEPS}: ${STEP_NAMES[$i]} ──${X}"
}

end_step() {
    local i=$(( $1 - 1 ))
    local elapsed=$(( $(date +%s) - _step_start_ts ))
    local label
    (( elapsed < 60 )) && label="${elapsed}s" || label="$(( elapsed/60 ))m $(( elapsed%60 ))s"
    _update_step $i done "$label"
    _update_footer
    ok "${STEP_NAMES[$i]} completed in ${label}"
}

# ── Draw UI ───────────────────────────────────────────────────────────────────
_draw_header

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 1 — System packages
# ═════════════════════════════════════════════════════════════════════════════
begin_step 1

echo -e "  ${D}Packages to install:${X}"
echo -e "    ${C}python3-venv python3-dev${X}       Python environment + headers"
echo -e "    ${C}python3-gi python3-gi-cairo${X}    GTK3 Python bindings (required for widget)"
echo -e "    ${C}gir1.2-gtk-3.0${X}                GTK3 introspection data"
echo -e "    ${C}portaudio19-dev libsndfile1${X}    Audio capture libraries"
echo -e "    ${C}xdotool${X}                        X11 input utility"
echo -e "\n  ${Y}You may be prompted for your sudo password.${X}"

run sudo apt-get update
run sudo apt-get install -y \
    python3-venv python3-dev \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1 \
    xdotool

end_step 1

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Virtual environment
# ═════════════════════════════════════════════════════════════════════════════
begin_step 2

echo -e "  ${D}Path: ${VENV_DIR}${X}"
echo -e "  ${D}--system-site-packages lets the venv see python3-gi (GTK3)${X}"

run mkdir -p "$INSTALL_DIR"
run python3 -m venv --system-site-packages "$VENV_DIR"

echo -e "\n  ${D}Verifying GTK3 is accessible inside the venv…${X}"
"$VENV_DIR/bin/python3" -c "
import gi; gi.require_version('Gtk','3.0')
from gi.repository import Gtk
v = f'{Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}'
print(f'  GTK3 {v} — OK')
" && true || die "GTK3 not visible inside venv. Check python3-gi installation."

end_step 2

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Install whisper-note
# ═════════════════════════════════════════════════════════════════════════════
begin_step 3

echo -e "  ${D}Source: TestPyPI  (test.pypi.org)${X}"
echo -e "  ${D}Dependencies: faster-whisper, openai, httpx, sounddevice, pynput…${X}"
echo -e "  ${D}Note: first run downloads the Whisper '${WHISPER_MODEL}' model (~${WHISPER_MODEL_SIZE:-74} MB, cached after that).${X}"

run "$VENV_DIR/bin/pip" install --upgrade pip

run "$VENV_DIR/bin/pip" install \
    --index-url https://test.pypi.org/simple/ \
    --extra-index-url https://pypi.org/simple/ \
    whisper-note

VER=$("$VENV_DIR/bin/whisper-note" --version 2>/dev/null || echo "unknown")
echo -e "\n  Installed: ${G}${VER}${X}"

end_step 3

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Environment file
# ═════════════════════════════════════════════════════════════════════════════
begin_step 4

echo -e "  ${D}File: ${ENV_FILE}${X}"
echo -e "  ${D}Permissions: 600 — readable only by you (protects API key)${X}"

run mkdir -p "$CONF_DIR"

cat > "$ENV_FILE" << ENVEOF
# Whisper Note — environment configuration
# ─────────────────────────────────────────
# Change any value:  whisper-note config set KEY=VALUE
# View all values:   whisper-note config show
# Apply changes:     systemctl --user restart whisper-note

GDK_BACKEND=x11

# Speech-to-text
WHISPER_MODEL=${WHISPER_MODEL}
WHISPER_COMPUTE_TYPE=${WHISPER_COMPUTE}

# Notes output
VOICE_NOTES_DIR=${VOICE_NOTES}

# LLM formatter (OpenAI-compatible — works with Ollama / OpenAI / Claude)
WN_LLM_URL=${WN_LLM_URL}
WN_LLM_KEY=${WN_LLM_KEY}
WN_LLM_MODEL=${WN_LLM_MODEL}
WN_LLM_TIMEOUT=${WN_LLM_TIMEOUT}
ENVEOF

chmod 600 "$ENV_FILE"
echo -e "\n  ${D}Written (API key hidden):${X}"
grep -v "^#" "$ENV_FILE" | grep -v "^$" | grep -v "WN_LLM_KEY" | sed 's/^/    /'
echo -e "    WN_LLM_KEY=${D}<hidden>${X}"

end_step 4

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Systemd service
# ═════════════════════════════════════════════════════════════════════════════
begin_step 5

echo -e "  ${D}Service file : ${SERVICE_FILE}${X}"
echo -e "  ${D}Env file     : ${ENV_FILE}${X}"
echo -e "  ${D}Auto-starts on every graphical login.${X}"

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

sleep 2
echo -e "\n  ${D}Service status:${X}"
systemctl --user status whisper-note --no-pager | head -10 | sed 's/^/    /'

end_step 5

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Desktop entry
# ═════════════════════════════════════════════════════════════════════════════
begin_step 6

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

update-desktop-database "$APPS_DIR" 2>/dev/null || true

end_step 6

# ═════════════════════════════════════════════════════════════════════════════
#  Done
# ═════════════════════════════════════════════════════════════════════════════
TOTAL=$(( $(date +%s) - INSTALL_START ))
TOTAL_M=$(( TOTAL/60 )); TOTAL_S=$(( TOTAL%60 ))

# Reset scroll region before final output
tput csr 0 $(( TERM_ROWS - 1 ))
tput cup $(( SCROLL_START + 2 )) 0

echo
echo -e "${G}${W}"
echo -e "  ╔══════════════════════════════════════════════════════════╗"
printf  "  ║   ✓  Done!  All 6 steps completed in %dm %02ds.%*s║\n" \
        $TOTAL_M $TOTAL_S $(( 22 - ${#TOTAL_M} - ${#TOTAL_S} )) ''
echo -e "  ╚══════════════════════════════════════════════════════════╝${X}"
echo
echo -e "  The ${W}Whisper Note${X} widget is now running in the ${W}top-right corner${X}"
echo -e "  of your screen and auto-starts on every login."
echo
echo -e "  ${W}How to record${X}"
echo -e "    ${Y}Hold${X}    Ctrl+Alt+Space  →  Widget turns red   (recording)"
echo -e "    ${Y}Release${X} any key         →  Widget turns amber (transcribing)"
echo -e "    ${Y}Done${X}                    →  Widget turns green (note saved)"
echo
echo -e "  ${W}Notes saved to${X}  ${C}${VOICE_NOTES}${X}"
echo
echo -e "  ${W}Service${X}"
echo -e "    ${C}systemctl --user start   whisper-note${X}"
echo -e "    ${C}systemctl --user stop    whisper-note${X}"
echo -e "    ${C}journalctl --user -u whisper-note -f${X}    (live logs)"
echo
echo -e "  ${W}Change settings later${X}"
echo -e "    ${C}whisper-note config show${X}"
echo -e "    ${C}whisper-note config set WHISPER_MODEL=small${X}"
echo -e "    ${C}whisper-note config set WN_LLM_MODEL=gpt-4o-mini${X}"
echo
