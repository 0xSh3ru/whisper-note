#!/usr/bin/env bash
# =============================================================================
#  Whisper Note — Interactive Installer  (Ubuntu only)
#
#  Phase 1 — whiptail wizard  (3 sections, collects all config)
#  Phase 2 — installation     (full-screen dialog per step, live output)
#
#  Phase 2 layout (redrawn for every step):
#  ┌─────────────────────────────────────────────────────────────────┐
#  │  🎙 WHISPER NOTE INSTALLER           Step N of 7               │  banner
#  ├─────────────────────────────────────────────────────────────────┤
#  │  ▶ Step Name                                                    │  title
#  │  Description of what this step does                             │  desc
#  ├── Live Output ──────────────────────────────────────────────────┤
#  │  [command output streams here — scrolls]                        │  ← scroll
#  │                                                                 │
#  ├── Progress ─────────────────────────────────────────────────────┤
#  │  [✓] 1. Step one (12s)   [✓] 2. Step two (8s)   [▶] 3. ...    │  checklist
#  │  ░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓  3 / 7   elapsed 1m 05s              │  progress
#  └─────────────────────────────────────────────────────────────────┘
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; Y='\033[0;33m'; G='\033[0;32m'; GR='\033[90m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1m'; D='\033[2m'
BG_D='\033[40m'; X='\033[0m'

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

# ── Helpers ───────────────────────────────────────────────────────────────────
die()  { tput cnorm; echo -e "\n${R}  ✗  ${1}${X}" >&2; exit 1; }
run()  { echo -e "${D}${C}  \$ $*${X}"; "$@"; }
ok()   { echo -e "${G}  ✓  ${1}${X}"; }
_wt()  { whiptail --backtitle "  🎙  Whisper Note Installer" "$@"; }

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

The setup has 3 short sections:

  ┌─ Section 1 of 3 ─ Speech-to-Text ──────────────────┐
  │  Choose the local Whisper model and settings        │
  └─────────────────────────────────────────────────────┘
  ┌─ Section 2 of 3 ─ AI Formatter (LLM) ──────────────┐
  │  Choose the AI that formats your transcripts        │
  └─────────────────────────────────────────────────────┘
  ┌─ Section 3 of 3 ─ Review & Install ─────────────────┐
  │  Check all settings, then start the installation    │
  └─────────────────────────────────────────────────────┘

Use arrow keys to navigate.  Tab switches between OK / Cancel.

Press Enter to begin." 24 65

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 1 of 3 — Speech-to-Text
# ══════════════════════════════════════════════════════════════════════════════
_wt --backtitle "  🎙  Whisper Note Installer  │  Section 1 of 3 — Speech-to-Text" \
    --title "  1a — Whisper Model  " \
    --radiolist \
"Choose the speech-to-text model.

The model is downloaded during installation and cached locally.
Larger models are more accurate but need more CPU / RAM / disk.

  Arrow keys to navigate  •  Space to select  •  Enter to confirm" \
    19 68 5 \
    "base"     "  74 MB  ·  Fast, good accuracy         ← Recommended" ON  \
    "tiny"     "  39 MB  ·  Fastest, basic accuracy"                    OFF \
    "small"    " 244 MB  ·  Better accuracy"                            OFF \
    "medium"   " 769 MB  ·  High accuracy  (slow on CPU)"               OFF \
    "large-v3" "1500 MB  ·  Best accuracy  (needs good hardware)"       OFF \
    2> /tmp/wn_model.txt || die "Installation cancelled."
WHISPER_MODEL=$(cat /tmp/wn_model.txt)

_wt --backtitle "  🎙  Whisper Note Installer  │  Section 1 of 3 — Speech-to-Text" \
    --title "  1b — Compute Type  " \
    --radiolist \
"How should the Whisper model run inference on your machine?

'int8'    is fastest on CPU — works on any hardware.
'float16' requires an NVIDIA GPU with CUDA drivers.
'float32' is most compatible but the slowest option." \
    15 64 3 \
    "int8"    "  Fastest on CPU       ← Recommended for most users"  ON  \
    "float16" "  Requires CUDA GPU  (fastest if you have one)"        OFF \
    "float32" "  Most compatible, slowest"                            OFF \
    2> /tmp/wn_compute.txt || die "Installation cancelled."
WHISPER_COMPUTE=$(cat /tmp/wn_compute.txt)

_wt --backtitle "  🎙  Whisper Note Installer  │  Section 1 of 3 — Speech-to-Text" \
    --title "  1c — Notes Directory  " \
    --inputbox \
"Where should Whisper Note save your markdown notes?

The directory is created automatically if it does not exist.
Change it later:  whisper-note config set VOICE_NOTES_DIR=/new/path" \
    12 65 "$HOME/VoiceNotes" \
    2> /tmp/wn_notes.txt || die "Installation cancelled."
VOICE_NOTES=$(cat /tmp/wn_notes.txt)
[[ -n "$VOICE_NOTES" ]] || VOICE_NOTES="$HOME/VoiceNotes"

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 2 of 3 — LLM Formatter
# ══════════════════════════════════════════════════════════════════════════════
_wt --backtitle "  🎙  Whisper Note Installer  │  Section 2 of 3 — AI Formatter" \
    --title "  2a — AI Provider  " \
    --menu \
"Whisper Note uses an AI model to format your voice transcript
into clean, structured Markdown.

  Ollama runs on YOUR machine — no API key, no cost.
  OpenAI and Claude are cloud APIs and require a paid key." \
    16 68 4 \
    "ollama" "  Local Ollama     (no key needed — runs on your machine)" \
    "openai" "  OpenAI API       (requires sk-... key)" \
    "claude" "  Anthropic Claude  (requires sk-ant-... key)" \
    "custom" "  Custom OpenAI-compatible endpoint" \
    2> /tmp/wn_provider.txt || die "Installation cancelled."
PROVIDER=$(cat /tmp/wn_provider.txt)
[[ -n "$PROVIDER" ]] || die "No AI provider selected."

case "$PROVIDER" in
    ollama) _URL="http://127.0.0.1:11434/v1"; _KEY="ollama"; _MODEL="qwen3:4b" ;;
    openai) _URL="https://api.openai.com/v1";  _KEY="";       _MODEL="gpt-4o-mini" ;;
    claude) _URL="https://api.anthropic.com/v1"; _KEY="";     _MODEL="claude-haiku-4-5-20251001" ;;
    custom) _URL="http://localhost:11434/v1";   _KEY="";       _MODEL="" ;;
    *)      _URL="http://localhost:11434/v1";   _KEY="";       _MODEL="" ;;
esac

_wt --backtitle "  🎙  Whisper Note Installer  │  Section 2 of 3 — AI Formatter" \
    --title "  2b — LLM Model  " \
    --inputbox \
"Enter the model name for AI formatting.

Provider: ${PROVIDER}

Common choices:
  Ollama  →  qwen3:4b  /  llama3.2  /  mistral
  OpenAI  →  gpt-4o-mini  /  gpt-4o
  Claude  →  claude-haiku-4-5-20251001

Change later:  whisper-note config set WN_LLM_MODEL=<model>" \
    16 65 "$_MODEL" \
    2> /tmp/wn_llm_model.txt || die "Installation cancelled."
WN_LLM_MODEL=$(cat /tmp/wn_llm_model.txt)
[[ -n "$WN_LLM_MODEL" ]] || WN_LLM_MODEL="$_MODEL"

if [[ "$PROVIDER" == "ollama" ]]; then
    WN_LLM_KEY="ollama"
else
    _wt --backtitle "  🎙  Whisper Note Installer  │  Section 2 of 3 — AI Formatter" \
        --title "  2c — API Key  " \
        --passwordbox \
"Enter your ${PROVIDER} API key.  Input is hidden as you type.

Stored in: ${ENV_FILE}
Permissions: 600 — readable ONLY by you.

Change later:  whisper-note config set WN_LLM_KEY=<new-key>" \
        13 65 \
        2> /tmp/wn_key.txt || die "Installation cancelled."
    WN_LLM_KEY=$(cat /tmp/wn_key.txt)
    [[ -n "$WN_LLM_KEY" ]] || die "API key is required for ${PROVIDER}."
fi

_wt --backtitle "  🎙  Whisper Note Installer  │  Section 2 of 3 — AI Formatter" \
    --title "  2d — API URL  " \
    --inputbox \
"API endpoint URL for ${PROVIDER}.

Pre-filled for your chosen provider.
Only change this if you use a proxy or self-hosted instance." \
    11 68 "$_URL" \
    2> /tmp/wn_url.txt || die "Installation cancelled."
WN_LLM_URL=$(cat /tmp/wn_url.txt)
[[ -n "$WN_LLM_URL" ]] || WN_LLM_URL="$_URL"

_wt --backtitle "  🎙  Whisper Note Installer  │  Section 2 of 3 — AI Formatter" \
    --title "  2e — Request Timeout  " \
    --inputbox \
"Maximum seconds to wait for a formatting response.

  Cloud APIs  (OpenAI / Claude)  :  30–60 seconds is plenty
  Ollama on CPU (no GPU)         :  300 seconds or more

Change later:  whisper-note config set WN_LLM_TIMEOUT=60" \
    13 65 "300" \
    2> /tmp/wn_timeout.txt || die "Installation cancelled."
WN_LLM_TIMEOUT=$(cat /tmp/wn_timeout.txt)
[[ "$WN_LLM_TIMEOUT" =~ ^[0-9]+$ ]] || WN_LLM_TIMEOUT=300

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 3 of 3 — Review & confirm
# ══════════════════════════════════════════════════════════════════════════════
_wt --backtitle "  🎙  Whisper Note Installer  │  Section 3 of 3 — Review & Install" \
    --title "  Review Your Settings  " --yesno \
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

Select  Yes  to start,  No  to cancel." \
24 65 || { clear; echo -e "\n  Cancelled."; exit 0; }

# Clean up temp files
rm -f /tmp/wn_model.txt /tmp/wn_compute.txt /tmp/wn_notes.txt \
       /tmp/wn_provider.txt /tmp/wn_llm_model.txt /tmp/wn_key.txt \
       /tmp/wn_url.txt /tmp/wn_timeout.txt

# =============================================================================
#  PHASE 2 — Installation  (full-screen dialog per step)
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
STEP_DESC=(
    "Installing GTK3, Python venv, PortAudio and other system libraries via apt."
    "Creating a dedicated Python environment with access to system GTK3 bindings."
    "Downloading whisper-note plus the [http] formatter backend (openai, httpx)."
    "Downloading the '${WHISPER_MODEL}' speech-to-text model from HuggingFace Hub."
    "Writing your settings to ${ENV_FILE} (permissions: 600)."
    "Registering the systemd user service — auto-starts on every login."
    "Registering the desktop entry for the application launcher."
)
STEP_EST=( "~1-3 min" "~10 sec" "~2-5 min" "~1-10 min" "<1 sec" "~5 sec" "<1 sec" )
STEP_STATE=( pending pending pending pending pending pending pending )
STEP_ACTUAL=( "" "" "" "" "" "" "" )
N_STEPS=${#STEP_NAMES[@]}

INSTALL_START=$(date +%s)
_step_start_ts=0

# ── Layout constants (recalculate each time terminal is redrawn) ──────────────
_calc_layout() {
    TR=$(tput lines)
    TC=$(tput cols)
    # Dialog rows:
    #   0        : blank
    #   1        : top border
    #   2        : banner / step counter
    #   3        : step title
    #   4        : description
    #   5        : output separator
    #   6..TR-11 : live output (scroll region)
    #   TR-10    : bottom of output
    #   TR-9     : progress separator
    #   TR-8..TR-2 : checklist (7 steps)
    #   TR-1     : bottom border
    DIALOG_TOP=0
    BANNER_ROW=1
    TITLE_ROW=2
    DESC_ROW=3
    OUT_SEP_ROW=4
    OUT_TOP=5
    OUT_BOT=$(( TR - N_STEPS - 4 ))
    PROG_SEP_ROW=$(( TR - N_STEPS - 3 ))
    STEP_ROW_0=$(( TR - N_STEPS - 2 ))   # row of step 0 in footer
    BOT_ROW=$(( TR - 1 ))
}

# ── Draw the full-screen dialog frame ─────────────────────────────────────────
_draw_frame() {
    local cur_step=$1   # 1-based
    _calc_layout
    tput civis          # hide cursor while redrawing
    tput cup 0 0; tput ed

    # ── Top border ────────────────────────────────────────────────────────────
    printf "${C}  ╔"; printf '═%.0s' $(seq 1 $(( TC - 4 ))); printf "╗${X}\n"

    # ── Banner ────────────────────────────────────────────────────────────────
    local step_label="Step ${cur_step} of ${N_STEPS}"
    local title_str="  🎙  WHISPER NOTE INSTALLER"
    local rpad=$(( TC - ${#title_str} - ${#step_label} - 4 ))
    [[ $rpad -lt 1 ]] && rpad=1
    printf "${C}  ║${W}${title_str}${X}${C}%*s${Y}${step_label}${C}  ║${X}\n" \
           $rpad ''

    # ── Step title ────────────────────────────────────────────────────────────
    local sname="${STEP_NAMES[$(( cur_step - 1 ))]}"
    printf "${C}  ╠"; printf '═%.0s' $(seq 1 $(( TC - 4 ))); printf "╣${X}\n"
    local spad=$(( TC - ${#sname} - 9 ))
    [[ $spad -lt 1 ]] && spad=1
    printf "${C}  ║${X}  ${Y}▶${X}  ${W}%-*s${X}${C}  ║${X}\n" \
           $(( TC - 8 )) "$sname"

    # ── Description ───────────────────────────────────────────────────────────
    local sdesc="${STEP_DESC[$(( cur_step - 1 ))]}"
    printf "${C}  ║${X}  ${D}%-*s${X}${C}  ║${X}\n" $(( TC - 8 )) "$sdesc"

    # ── Output separator ──────────────────────────────────────────────────────
    printf "${C}  ╠"; printf '─%.0s' $(seq 1 $(( TC - 4 ))); printf "╣${X}\n"

    # ── Output area (blank lines) ─────────────────────────────────────────────
    for (( r=OUT_TOP; r<=OUT_BOT; r++ )); do
        printf "${C}  ║${X}%*s${C}  ║${X}\n" $(( TC - 6 )) ''
    done

    # ── Progress separator ────────────────────────────────────────────────────
    printf "${C}  ╠"; printf '─%.0s' $(seq 1 $(( TC - 4 ))); printf "╣${X}\n"

    # ── Checklist footer ──────────────────────────────────────────────────────
    _redraw_checklist

    # ── Bottom border ─────────────────────────────────────────────────────────
    tput cup $BOT_ROW 0
    printf "${C}  ╚"; printf '═%.0s' $(seq 1 $(( TC - 4 ))); printf "╝${X}"

    # ── Set scroll region to output area ─────────────────────────────────────
    tput csr $OUT_TOP $OUT_BOT
    tput cup $OUT_TOP 4
    tput cnorm  # restore cursor
}

# ── Redraw just the checklist rows ────────────────────────────────────────────
_redraw_checklist() {
    local done=0
    for s in "${STEP_STATE[@]}"; do [[ "$s" == "done" ]] && (( done++ )) || true; done
    local e=$(( $(date +%s) - INSTALL_START ))
    local m=$(( e/60 )) s=$(( e%60 ))

    # ── Bar: ▓▓▓▓▓░░░░ X/N  Ns ───────────────────────────────────────────────
    local bar_w=$(( TC - 28 )); [[ $bar_w -lt 10 ]] && bar_w=10
    local filled=$(( done * bar_w / N_STEPS ))
    local empty=$(( bar_w - filled ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="▓"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done

    # Draw steps
    for (( i=0; i<N_STEPS; i++ )); do
        tput cup $(( STEP_ROW_0 + i )) 0
        tput el
        local n=$(( i+1 )) nm="${STEP_NAMES[$i]}" act="${STEP_ACTUAL[$i]}"
        local nm_w=$(( TC - 22 )); [[ $nm_w -lt 10 ]] && nm_w=10
        case "${STEP_STATE[$i]}" in
          pending) printf "  ${C}║${X}  ${D}[ ]  %s. %-*s  %-8s${X}${C}  ║${X}" \
                          "$n" $nm_w "$nm" "${STEP_EST[$i]}" ;;
          running) printf "  ${C}║${X}  ${Y}[▶]  %s. %-*s  %-8s${X}${C}  ║${X}" \
                          "$n" $nm_w "$nm" "running…" ;;
          done)    printf "  ${C}║${X}  ${G}[✓]  %s. %-*s  %-8s${X}${C}  ║${X}" \
                          "$n" $nm_w "$nm" "$act" ;;
          failed)  printf "  ${C}║${X}  ${R}[✗]  %s. %-*s  %-8s${X}${C}  ║${X}" \
                          "$n" $nm_w "$nm" "FAILED" ;;
        esac
    done

    # Progress bar row
    tput cup $(( STEP_ROW_0 + N_STEPS )) 0; tput el
    printf "  ${C}║${X}  ${G}${bar}${X}  ${W}%s/%s${X}  ${D}elapsed: %dm %02ds${X}%*s${C}  ║${X}" \
           "$done" "$N_STEPS" "$m" "$s" \
           $(( TC - bar_w - 26 )) ''
}

# ── Update one step state and redraw footer ────────────────────────────────────
_update_step() {
    local i=$1 state=$2 actual="${3:-}"
    STEP_STATE[$i]=$state
    STEP_ACTUAL[$i]=$actual
    tput sc
    _redraw_checklist
    tput rc
}

# ── Restore terminal cleanly on exit ──────────────────────────────────────────
_cleanup() {
    tput csr 0 $(( $(tput lines) - 1 )) 2>/dev/null || true
    tput cup $(( $(tput lines) - 1 )) 0 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    echo
}
trap _cleanup EXIT INT TERM

# ── Step lifecycle ────────────────────────────────────────────────────────────
begin_step() {
    _step_start_ts=$(date +%s)
    _draw_frame "$1"
    _update_step $(( $1 - 1 )) running
    # Indent output inside the dialog box
    echo -e "  ${D}Starting…${X}"
}

end_step() {
    local i=$(( $1 - 1 ))
    local e=$(( $(date +%s) - _step_start_ts ))
    local l; (( e < 60 )) && l="${e}s" || l="$(( e/60 ))m $(( e%60 ))s"
    _update_step $i done "$l"
    echo -e "\n  ${G}✓  ${STEP_NAMES[$i]} — done in ${l}${X}"
    sleep 0.4   # brief pause so user can read the ✓
}

# =======================================================================
#  STEP 1 — System packages
# =======================================================================
begin_step 1
echo -e "  ${D}packages: python3-venv python3-dev python3-gi python3-gi-cairo${X}"
echo -e "  ${D}          gir1.2-gtk-3.0 portaudio19-dev libsndfile1 xdotool${X}"
echo -e "\n  ${Y}  ⚠  sudo required — you may be prompted for a password${X}\n"
run sudo apt-get update
run sudo apt-get install -y \
    python3-venv python3-dev \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1 \
    xdotool
end_step 1

# =======================================================================
#  STEP 2 — Virtual environment
# =======================================================================
begin_step 2
echo -e "  ${D}Path: ${VENV_DIR}${X}"
echo -e "  ${D}--system-site-packages exposes python3-gi (GTK3) to the venv.${X}\n"
run mkdir -p "$INSTALL_DIR"
run python3 -m venv --system-site-packages "$VENV_DIR"
echo -e "\n  ${D}Verifying GTK3 is visible inside the venv…${X}"
"$VENV_DIR/bin/python3" -c "
import gi; gi.require_version('Gtk','3.0')
from gi.repository import Gtk
print(f'  GTK3 {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()} — OK')
" || die "GTK3 not visible in venv. Check python3-gi installation."
end_step 2

# =======================================================================
#  STEP 3 — Install whisper-note
# =======================================================================
begin_step 3
echo -e "  ${D}Source: TestPyPI  (test.pypi.org) + PyPI for dependencies${X}"
echo -e "  ${D}Backend: installing the [http] extra (openai + httpx) for ${PROVIDER}.${X}\n"
run "$VENV_DIR/bin/pip" install --upgrade pip
echo
run "$VENV_DIR/bin/pip" install \
    --index-url https://test.pypi.org/simple/ \
    --extra-index-url https://pypi.org/simple/ \
    "whisper-note[http]"
VER=$("$VENV_DIR/bin/whisper-note" --version 2>/dev/null || echo "unknown")
echo -e "\n  Installed: ${G}${VER}${X}"
end_step 3

# =======================================================================
#  STEP 4 — Download Whisper model
# =======================================================================
begin_step 4
case "$WHISPER_MODEL" in
    tiny)     _SZ="~39 MB"  ;; base)  _SZ="~74 MB"  ;;
    small)    _SZ="~244 MB" ;; medium) _SZ="~769 MB" ;;
    large-v3) _SZ="~1.5 GB" ;; *)     _SZ="unknown" ;;
esac
echo -e "  ${D}Model : ${WHISPER_MODEL}  (${_SZ})${X}"
echo -e "  ${D}Cache : ~/.cache/huggingface/hub  (reused on future installs)${X}"
echo -e "  ${D}Downloading — progress bars appear below:${X}\n"
"$VENV_DIR/bin/python3" - << PYEOF
import sys, os
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
model_name = "${WHISPER_MODEL}"
compute    = "${WHISPER_COMPUTE}"
print(f"  Fetching faster-whisper / {model_name}  [{compute}]...\n")
sys.stdout.flush()
try:
    from faster_whisper import WhisperModel
    m = WhisperModel(model_name, device="cpu", compute_type=compute)
    del m
    print(f"\n  Model '{model_name}' downloaded and verified.")
except Exception as e:
    print(f"\n  Warning: pre-download failed ({e})")
    print(  "  The model will download automatically on first recording.")
    sys.exit(0)
PYEOF
end_step 4

# =======================================================================
#  STEP 5 — Environment file
# =======================================================================
begin_step 5
echo -e "  ${D}Writing to: ${ENV_FILE}  (permissions: 600)${X}\n"
run mkdir -p "$CONF_DIR"
cat > "$ENV_FILE" << ENVEOF
# Whisper Note — environment configuration
# Change: whisper-note config set KEY=VALUE
# View:   whisper-note config show
# Apply:  systemctl --user restart whisper-note

GDK_BACKEND=x11
WHISPER_MODEL=${WHISPER_MODEL}
WHISPER_COMPUTE_TYPE=${WHISPER_COMPUTE}
VOICE_NOTES_DIR=${VOICE_NOTES}
# This installer configures the OpenAI-compatible HTTP backend.
# The app default is the local llama.cpp/GGUF backend; pin http explicitly.
WN_LLM_BACKEND=http
WN_LLM_URL=${WN_LLM_URL}
WN_LLM_KEY=${WN_LLM_KEY}
WN_LLM_MODEL=${WN_LLM_MODEL}
WN_LLM_TIMEOUT=${WN_LLM_TIMEOUT}
ENVEOF
chmod 600 "$ENV_FILE"
echo -e "  ${D}Values written (key hidden):${X}"
grep -v "^#" "$ENV_FILE" | grep -v "^$" | grep -v "WN_LLM_KEY" | sed 's/^/    /'
echo -e "    WN_LLM_KEY=${D}<hidden>${X}"
end_step 5

# =======================================================================
#  STEP 6 — Systemd service
# =======================================================================
begin_step 6
echo -e "  ${D}Service file : ${SERVICE_FILE}${X}"
echo -e "  ${D}Env file     : ${ENV_FILE}${X}"
echo -e "  ${D}Auto-starts on every graphical session login.${X}\n"
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
systemctl --user status whisper-note --no-pager | head -8 | sed 's/^/    /'
end_step 6

# =======================================================================
#  STEP 7 — Desktop entry
# =======================================================================
begin_step 7
APPS_DIR="$HOME/.local/share/applications"
echo -e "  ${D}Writing: ${APPS_DIR}/whisper-note.desktop${X}\n"
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
#  Done — restore full screen and show completion dialog
# =============================================================================
TOTAL=$(( $(date +%s) - INSTALL_START ))
TM=$(( TOTAL/60 )); TS=$(( TOTAL%60 ))

tput csr 0 $(( $(tput lines) - 1 ))
tput cup 0 0; tput ed

_wt --backtitle "  🎙  Whisper Note Installer  │  Complete" \
    --title "  ✓  Installation Complete  " --msgbox \
"All 7 steps completed successfully in ${TM}m ${TS}s!

The Whisper Note widget is now running in the top-right
corner of your screen and starts automatically on login.

  ── How to use ───────────────────────────────────────
  Hold    Ctrl+Alt+Space  →  Recording starts  (red)
  Release any key         →  Transcribing…     (amber)
  Done                    →  Note saved!        (green)
  Esc                     →  Quit

  ── Notes saved to ───────────────────────────────────
  ${VOICE_NOTES}

  ── Service commands ─────────────────────────────────
  systemctl --user stop    whisper-note
  systemctl --user start   whisper-note
  journalctl --user -u whisper-note -f

  ── Change settings ──────────────────────────────────
  whisper-note config show
  whisper-note config set WHISPER_MODEL=small
  whisper-note config set WN_LLM_MODEL=gpt-4o-mini

Press Enter to exit the installer." \
30 65
