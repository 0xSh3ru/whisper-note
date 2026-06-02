#!/usr/bin/env bash
# =============================================================================
#  Whisper Note — Interactive Installer  (Ubuntu only)
#
#  Flow:
#    Phase 1 — whiptail wizard  (3 sections, one topic at a time)
#              Section 1/3: Speech-to-Text settings
#              Section 2/3: LLM Formatter settings
#              Section 3/3: Review & confirm
#
#    Phase 2 — installation    (fixed checklist + scrolling log)
#              [✓] System packages
#              [✓] Python virtual environment
#              [✓] Install whisper-note
#              [▶] Download Whisper model        ← with live progress bar
#              [ ] Write environment file
#              [ ] Register systemd service
#              [ ] Register desktop entry
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; Y='\033[0;33m'; G='\033[0;32m'; GR='\033[90m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1m'; D='\033[2m'; X='\033[0m'

# ── whiptail dark-cyan theme ──────────────────────────────────────────────────
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

BACKTITLE="  🎙  Whisper Note Installer"

# ── Utility ───────────────────────────────────────────────────────────────────
die()  { echo -e "\n${R}  ✗  ${1}${X}" >&2; exit 1; }
run()  { echo -e "\n${D}${C}  \$ $*${X}"; "$@"; }
ok()   { echo -e "${G}  ✓  ${1}${X}"; }

_wt()  { whiptail --backtitle "$BACKTITLE" "$@"; }

# ── Ubuntu guard ──────────────────────────────────────────────────────────────
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
OS_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
UBUNTU_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "?")
[[ "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"ubuntu"* ]] || \
    die "This installer requires Ubuntu (detected: ${OS_ID:-unknown})."

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/whisper-note"
VENV_DIR="$INSTALL_DIR/venv"
CONF_DIR="$HOME/.config/whisper-note"
ENV_FILE="$CONF_DIR/env"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/whisper-note.service"

# =============================================================================
#  PHASE 1 — Configuration wizard  (whiptail)
# =============================================================================

# ── Welcome ───────────────────────────────────────────────────────────────────
_wt --title "  Welcome to Whisper Note  " --msgbox \
"Ubuntu ${UBUNTU_VER} detected.  You are about to install:

  🎙  Whisper Note — Voice-to-Markdown note taker

The wizard has 3 short sections:

  ┌─ Section 1 of 3 ─ Speech-to-Text ──────────────────┐
  │  Choose the local Whisper model and settings        │
  └─────────────────────────────────────────────────────┘
  ┌─ Section 2 of 3 ─ AI Formatter (LLM) ──────────────┐
  │  Choose the AI that formats your transcripts        │
  └─────────────────────────────────────────────────────┘
  ┌─ Section 3 of 3 ─ Review & Install ─────────────────┐
  │  Check settings, then start the installation        │
  └─────────────────────────────────────────────────────┘

Use arrow keys to navigate.  Tab switches between OK/Cancel.

Press Enter to begin." 24 65

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 1 of 3 — Speech-to-Text
# ══════════════════════════════════════════════════════════════════════════════
BACKTITLE="  🎙  Whisper Note Installer  │  Section 1 of 3 — Speech-to-Text"

# 1a. Whisper model
WHISPER_MODEL=$( _wt \
    --title "  Whisper Model  " \
    --radiolist \
"Choose the speech-to-text model.

The model downloads automatically on install (~74 MB for 'base').
Larger models are more accurate but need more CPU/RAM.

  Use arrow keys to highlight  •  Space to select  •  Enter to confirm" \
    19 68 5 \
    "base"     "  74 MB  ·  Fast, good accuracy       ← Recommended" ON  \
    "tiny"     "  39 MB  ·  Fastest, basic accuracy"                  OFF \
    "small"    " 244 MB  ·  Better accuracy"                          OFF \
    "medium"   " 769 MB  ·  High accuracy (slow on CPU)"              OFF \
    "large-v3" "1500 MB  ·  Best accuracy (needs good hardware)"      OFF \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# 1b. Compute type
WHISPER_COMPUTE=$( _wt \
    --title "  Compute Type  " \
    --radiolist \
"How should Whisper run inference?

'int8'  is fastest on CPU and works on any hardware.
'float16' requires an NVIDIA GPU with CUDA support.
'float32' is the most compatible but slowest option." \
    15 64 3 \
    "int8"    "  Fastest on CPU  ← Recommended for most users"  ON  \
    "float16" "  Requires CUDA GPU (faster if available)"        OFF \
    "float32" "  Most compatible, slowest"                       OFF \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# 1c. Notes directory
VOICE_NOTES=$( _wt \
    --title "  Notes Directory  " \
    --inputbox \
"Where should Whisper Note save your markdown notes?

The directory will be created automatically if it does not exist.
You can change this later with:
  whisper-note config set VOICE_NOTES_DIR=/new/path" \
    13 65 "$HOME/VoiceNotes" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."
[[ -n "$VOICE_NOTES" ]] || VOICE_NOTES="$HOME/VoiceNotes"

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 2 of 3 — LLM Formatter
# ══════════════════════════════════════════════════════════════════════════════
BACKTITLE="  🎙  Whisper Note Installer  │  Section 2 of 3 — AI Formatter"

# 2a. Provider
PROVIDER=$( _wt \
    --title "  AI Formatter Provider  " \
    --menu \
"Whisper Note uses an AI model to format your voice transcript
into clean, structured Markdown.

Choose your provider:

  Ollama runs on YOUR machine — no API key, no cost.
  OpenAI and Claude are cloud APIs that require a paid key." \
    18 68 4 \
    "ollama" "  Local Ollama    (no key, runs on your machine)" \
    "openai" "  OpenAI API      (requires sk-... key)" \
    "claude" "  Anthropic Claude (requires sk-ant-... key)" \
    "custom" "  Custom OpenAI-compatible endpoint" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."

# Pre-fill defaults per provider
case "$PROVIDER" in
    ollama) _URL="http://127.0.0.1:11434/v1"; _KEY="ollama";  _MODEL="qwen3:4b" ;;
    openai) _URL="https://api.openai.com/v1"; _KEY="";         _MODEL="gpt-4o-mini" ;;
    claude) _URL="https://api.anthropic.com/v1"; _KEY="";      _MODEL="claude-haiku-4-5-20251001" ;;
    custom) _URL="http://localhost:11434/v1"; _KEY="";          _MODEL="" ;;
esac

# 2b. Model name
WN_LLM_MODEL=$( _wt \
    --title "  LLM Model Name  " \
    --inputbox \
"Enter the model name for AI formatting.

Provider: ${PROVIDER}

Common choices:
  Ollama  →  qwen3:4b  /  llama3.2  /  mistral
  OpenAI  →  gpt-4o-mini  /  gpt-4o
  Claude  →  claude-haiku-4-5-20251001  /  claude-sonnet-4-6

You can change this later with:
  whisper-note config set WN_LLM_MODEL=<model>" \
    17 65 "$_MODEL" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."
[[ -n "$WN_LLM_MODEL" ]] || WN_LLM_MODEL="$_MODEL"

# 2c. API key (skipped for Ollama)
if [[ "$PROVIDER" == "ollama" ]]; then
    WN_LLM_KEY="ollama"
else
    WN_LLM_KEY=$( _wt \
        --title "  API Key  " \
        --passwordbox \
"Enter your ${PROVIDER} API key.  Input is hidden.

The key is stored in:
  ${ENV_FILE}
with permissions 600 — readable ONLY by you.

You can update it later with:
  whisper-note config set WN_LLM_KEY=<new-key>" \
        14 65 \
        3>&1 1>&2 2>&3 ) || die "Installation cancelled."
    [[ -n "$WN_LLM_KEY" ]] || die "API key is required for ${PROVIDER}."
fi

# 2d. API URL  (always shown so user can confirm or customise)
WN_LLM_URL=$( _wt \
    --title "  LLM API URL  " \
    --inputbox \
"API endpoint URL for ${PROVIDER}.

This is pre-filled for your chosen provider.
Only change this if you use a custom proxy or self-hosted instance." \
    12 68 "$_URL" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."
[[ -n "$WN_LLM_URL" ]] || WN_LLM_URL="$_URL"

# 2e. Timeout
WN_LLM_TIMEOUT=$( _wt \
    --title "  Request Timeout  " \
    --inputbox \
"Maximum seconds to wait for a formatting response.

  Cloud APIs  (OpenAI / Claude) : 30-60 s is plenty
  Ollama on CPU                 : 300 s or more (inference is slow)

You can change this later:
  whisper-note config set WN_LLM_TIMEOUT=60" \
    14 65 "300" \
    3>&1 1>&2 2>&3 ) || die "Installation cancelled."
[[ -n "$WN_LLM_TIMEOUT" ]] && [[ "$WN_LLM_TIMEOUT" =~ ^[0-9]+$ ]] || WN_LLM_TIMEOUT=300

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 3 of 3 — Review & confirm
# ══════════════════════════════════════════════════════════════════════════════
BACKTITLE="  🎙  Whisper Note Installer  │  Section 3 of 3 — Review & Install"

_wt --title "  Review Your Settings  " --yesno \
"Everything looks good?  Here is what will be installed:

  ── Speech-to-Text ───────────────────────────────────
  Whisper model    :  ${WHISPER_MODEL}
  Compute type     :  ${WHISPER_COMPUTE}
  Notes directory  :  ${VOICE_NOTES}

  ── AI Formatter ─────────────────────────────────────
  Provider         :  ${PROVIDER}
  LLM URL          :  ${WN_LLM_URL}
  LLM model        :  ${WN_LLM_MODEL}
  API key          :  $([ "$PROVIDER" = "ollama" ] && echo "not required" || echo "<set>")
  Timeout          :  ${WN_LLM_TIMEOUT}s

  ── Install path ─────────────────────────────────────
  ${INSTALL_DIR}

Select Yes to start installation, No to go back and cancel." \
24 65 || { echo -e "\n  Cancelled."; exit 0; }

# =============================================================================
#  PHASE 2 — Installation  (fixed checklist + scrolling log)
# =============================================================================

STEP_NAMES=(
    "Install system packages"
    "Create Python virtual environment"
    "Install whisper-note from PyPI"
    "Download Whisper model (${WHISPER_MODEL})"
    "Write environment file"
    "Register systemd service"
    "Register desktop entry"
)
STEP_EST=( "~1-3 min" "~10 sec" "~2-5 min" "~1-10 min" "<1 sec" "~5 sec" "<1 sec" )
STEP_STATE=( pending pending pending pending pending pending pending )
STEP_ACTUAL=( "" "" "" "" "" "" "" )
N_STEPS=${#STEP_NAMES[@]}

TERM_ROWS=$(tput lines)
TERM_COLS=$(tput cols)

BANNER_ROWS=6
STEP_ROW_START=7
FOOTER_ROW=$(( STEP_ROW_START + N_STEPS ))
SEP_ROW=$(( FOOTER_ROW + 1 ))
SCROLL_START=$(( SEP_ROW + 1 ))
INSTALL_START=$(date +%s)
_step_start_ts=0

# Restore terminal cleanly on exit / Ctrl+C
_cleanup() {
    tput csr 0 $(( $(tput lines) - 1 )) 2>/dev/null || true
    tput cup $(( $(tput lines) - 2 )) 0 2>/dev/null || true
    echo
}
trap _cleanup EXIT INT TERM

# ── Draw one step line ────────────────────────────────────────────────────────
_draw_step_line() {
    local i=$1 n=$(( $1 + 1 ))
    local name="${STEP_NAMES[$i]}" est="${STEP_EST[$i]}" actual="${STEP_ACTUAL[$i]}"
    local rpad=$(( TERM_COLS - 54 )); [[ $rpad -lt 0 ]] && rpad=0

    case "${STEP_STATE[$i]}" in
        pending) printf "  ${D}│  [ ]  %s. %-36s%-12s%*s│${X}\n" "$n" "$name" "$est" $rpad '' ;;
        running) printf "  ${Y}│  [▶]  %s. %-36s%-12s%*s│${X}\n" "$n" "$name" "⏱ running…" $rpad '' ;;
        done)    printf "  ${G}│  [✓]  %s. %-36s%-12s%*s│${X}\n" "$n" "$name" "$actual" $rpad '' ;;
        failed)  printf "  ${R}│  [✗]  %s. %-36s%-12s%*s│${X}\n" "$n" "$name" "FAILED" $rpad '' ;;
    esac
}

# ── Draw full header (once) ───────────────────────────────────────────────────
_draw_header() {
    tput cup 0 0; tput ed

    echo -e "${B}${W}"
    echo -e "  ╔══════════════════════════════════════════════════════════╗"
    echo -e "  ║   🎙  Whisper Note — Installing…                         ║"
    echo -e "  ║       Hold Ctrl+Alt+Space to record after install        ║"
    echo -e "  ╚══════════════════════════════════════════════════════════╝${X}"
    echo

    local rpad=$(( TERM_COLS - 58 )); [[ $rpad -lt 0 ]] && rpad=0
    printf "${D}  ┌─── Installation steps%*s┐${X}\n" $rpad ''
    for (( i=0; i<N_STEPS; i++ )); do _draw_step_line $i; done
    printf "${D}  └─── 0/%s done  •  starting…%*s┘${X}\n" "$N_STEPS" $(( rpad - 10 )) ''
    printf "${GR}  ── log output %s${X}\n" "$(printf '─%.0s' $(seq 1 $(( TERM_COLS - 18 ))))"

    tput csr $SCROLL_START $(( TERM_ROWS - 1 ))
    tput cup $SCROLL_START 0
}

# ── Update one step line in-place ─────────────────────────────────────────────
_update_step() {
    local i=$1 state=$2 actual="${3:-}"
    STEP_STATE[$i]=$state; STEP_ACTUAL[$i]=$actual
    tput sc
    tput cup $(( STEP_ROW_START + i )) 0; tput el
    _draw_step_line $i
    tput rc
}

# ── Update footer ─────────────────────────────────────────────────────────────
_update_footer() {
    local done=0
    for s in "${STEP_STATE[@]}"; do [[ "$s" == "done" ]] && (( done++ )) || true; done
    local e=$(( $(date +%s) - INSTALL_START )) m=$(( e/60 )) s=$(( e%60 ))
    local rpad=$(( TERM_COLS - 58 )); [[ $rpad -lt 0 ]] && rpad=0
    tput sc
    tput cup $FOOTER_ROW 0; tput el
    printf "${D}  └─── ${G}%s/%s done${D}  •  elapsed: %dm %02ds%*s┘${X}\n" \
           "$done" "$N_STEPS" "$m" "$s" $rpad ''
    tput rc
}

# ── Step lifecycle ────────────────────────────────────────────────────────────
begin_step() {
    local i=$(( $1 - 1 ))
    _step_start_ts=$(date +%s)
    _update_step $i running
    echo -e "\n${B}${W}  ── Step ${1}/${N_STEPS}: ${STEP_NAMES[$i]} ──────────────────${X}"
}

end_step() {
    local i=$(( $1 - 1 ))
    local e=$(( $(date +%s) - _step_start_ts ))
    local l; (( e < 60 )) && l="${e}s" || l="$(( e/60 ))m $(( e%60 ))s"
    _update_step $i done "$l"
    _update_footer
    ok "${STEP_NAMES[$i]} — done in ${l}"
}

# ── Draw header ───────────────────────────────────────────────────────────────
_draw_header

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 1 — System packages
# ═════════════════════════════════════════════════════════════════════════════
begin_step 1
echo -e "  ${D}Installing required apt packages:${X}"
echo -e "    ${C}python3-venv python3-dev${X}       Python environment"
echo -e "    ${C}python3-gi python3-gi-cairo${X}    GTK3 bindings (widget)"
echo -e "    ${C}gir1.2-gtk-3.0${X}                GTK3 introspection"
echo -e "    ${C}portaudio19-dev libsndfile1${X}    Audio capture"
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
echo -e "  ${D}--system-site-packages allows the venv to see python3-gi (GTK3).${X}"
run mkdir -p "$INSTALL_DIR"
run python3 -m venv --system-site-packages "$VENV_DIR"
echo -e "\n  ${D}Verifying GTK3 is visible inside the venv…${X}"
"$VENV_DIR/bin/python3" -c "
import gi; gi.require_version('Gtk','3.0')
from gi.repository import Gtk
print(f'  GTK3 {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()} — OK')
" || die "GTK3 not visible in venv — check python3-gi installation."
end_step 2

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Install whisper-note
# ═════════════════════════════════════════════════════════════════════════════
begin_step 3
echo -e "  ${D}Source: TestPyPI (test.pypi.org) with PyPI fallback for dependencies${X}"
run "$VENV_DIR/bin/pip" install --upgrade pip
echo
run "$VENV_DIR/bin/pip" install \
    --index-url https://test.pypi.org/simple/ \
    --extra-index-url https://pypi.org/simple/ \
    whisper-note
VER=$("$VENV_DIR/bin/whisper-note" --version 2>/dev/null || echo "unknown")
echo -e "\n  Installed: ${G}${VER}${X}"
end_step 3

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Download Whisper model
# ═════════════════════════════════════════════════════════════════════════════
begin_step 4

# Model sizes for display
case "$WHISPER_MODEL" in
    tiny)     _SIZE="~39 MB"  ;;
    base)     _SIZE="~74 MB"  ;;
    small)    _SIZE="~244 MB" ;;
    medium)   _SIZE="~769 MB" ;;
    large-v3) _SIZE="~1.5 GB" ;;
    *)        _SIZE="unknown" ;;
esac

echo -e "  ${D}Model   : ${WHISPER_MODEL}  (${_SIZE})${X}"
echo -e "  ${D}Cache   : ~/.cache/huggingface/hub  (reused on future installs)${X}"
echo -e "  ${D}Progress bar will appear below as each file downloads.${X}"
echo

# Inline Python: initialise WhisperModel which triggers HuggingFace download
"$VENV_DIR/bin/python3" - << PYEOF
import sys, os

# Suppress unrelated warnings
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

model_name = "${WHISPER_MODEL}"
compute    = "${WHISPER_COMPUTE}"

print(f"  Downloading faster-whisper/{model_name}  ({compute})…\n")
sys.stdout.flush()

try:
    from faster_whisper import WhisperModel
    # This triggers the HuggingFace Hub download with tqdm progress bars
    m = WhisperModel(model_name, device="cpu", compute_type=compute)
    del m
    print(f"\n  Model '{model_name}' downloaded and verified.")
except Exception as e:
    print(f"\n  Warning: model pre-download failed ({e})")
    print(  "  The model will download automatically on first recording.")
    sys.exit(0)   # non-fatal — app downloads it on first run anyway
PYEOF

end_step 4

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Environment file
# ═════════════════════════════════════════════════════════════════════════════
begin_step 5
echo -e "  ${D}File: ${ENV_FILE}  (permissions: 600)${X}"
run mkdir -p "$CONF_DIR"
cat > "$ENV_FILE" << ENVEOF
# Whisper Note — environment configuration
# Change values : whisper-note config set KEY=VALUE
# View values   : whisper-note config show
# Apply changes : systemctl --user restart whisper-note

GDK_BACKEND=x11

WHISPER_MODEL=${WHISPER_MODEL}
WHISPER_COMPUTE_TYPE=${WHISPER_COMPUTE}
VOICE_NOTES_DIR=${VOICE_NOTES}

WN_LLM_URL=${WN_LLM_URL}
WN_LLM_KEY=${WN_LLM_KEY}
WN_LLM_MODEL=${WN_LLM_MODEL}
WN_LLM_TIMEOUT=${WN_LLM_TIMEOUT}
ENVEOF
chmod 600 "$ENV_FILE"
echo -e "\n  ${D}Written values (key hidden):${X}"
grep -v "^#" "$ENV_FILE" | grep -v "^$" | grep -v "WN_LLM_KEY" | sed 's/^/    /'
echo -e "    WN_LLM_KEY=${D}<hidden>${X}"
end_step 5

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Systemd service
# ═════════════════════════════════════════════════════════════════════════════
begin_step 6
echo -e "  ${D}Service : ${SERVICE_FILE}${X}"
echo -e "  ${D}Env file: ${ENV_FILE}${X}"
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
update-desktop-database "$APPS_DIR" 2>/dev/null || true
end_step 7

# =============================================================================
#  Done
# =============================================================================
TOTAL=$(( $(date +%s) - INSTALL_START ))
TM=$(( TOTAL/60 )); TS=$(( TOTAL%60 ))

tput csr 0 $(( TERM_ROWS - 1 ))
tput cup $(( SCROLL_START + 2 )) 0

echo
echo -e "${G}${W}"
echo -e "  ╔══════════════════════════════════════════════════════════╗"
printf  "  ║   ✓  All 7 steps completed in %dm %02ds!%*s║\n" \
        $TM $TS $(( 22 - ${#TM} - ${#TS} )) ''
echo -e "  ╚══════════════════════════════════════════════════════════╝${X}"
echo
echo -e "  The ${W}Whisper Note${X} widget is now running in the ${W}top-right corner${X}"
echo -e "  of your screen. It auto-starts on every login."
echo
echo -e "  ${W}Record a note${X}"
echo -e "    ${Y}Hold${X}    Ctrl+Alt+Space  →  Widget turns red   (recording)"
echo -e "    ${Y}Release${X} any key         →  Widget turns amber (transcribing)"
echo -e "    ${Y}Done${X}                    →  Widget turns green (note saved)"
echo
echo -e "  ${W}Notes saved to${X}   ${C}${VOICE_NOTES}${X}"
echo
echo -e "  ${W}Service${X}"
echo -e "    ${C}systemctl --user stop    whisper-note${X}"
echo -e "    ${C}systemctl --user start   whisper-note${X}"
echo -e "    ${C}journalctl --user -u whisper-note -f${X}"
echo
echo -e "  ${W}Change a setting${X}"
echo -e "    ${C}whisper-note config set WHISPER_MODEL=small${X}"
echo -e "    ${C}whisper-note config set WN_LLM_MODEL=gpt-4o-mini${X}"
echo -e "    ${C}whisper-note config show${X}"
echo
