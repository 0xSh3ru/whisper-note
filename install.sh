#!/usr/bin/env bash
# =============================================================================
#  Whisper Note — Interactive Installer  (Ubuntu only)
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
R='\033[0;31m'  Y='\033[0;33m'  G='\033[0;32m'
B='\033[1;34m'  W='\033[1m'     X='\033[0m'

info()  { echo -e "${B}=>${X} $*"; }
ok()    { echo -e "${G}  ✓${X}  $*"; }
warn()  { echo -e "${Y}  ⚠${X}  $*"; }
die()   { echo -e "${R}  ✗  $*${X}" >&2; exit 1; }
ask()   { echo -en "${W}  $1${X} [${Y}$2${X}]: "; read -r _ans; echo "${_ans:-$2}"; }
ask_secret() { echo -en "${W}  $1${X} [leave blank to skip]: ";
               read -rs _sec; echo; echo "$_sec"; }

# ── Ubuntu guard ─────────────────────────────────────────────────────────────
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
OS_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")

if [[ "$OS_ID" != "ubuntu" && "$OS_LIKE" != *"ubuntu"* ]]; then
    die "This installer requires Ubuntu (detected: ${OS_ID:-unknown}). Aborting."
fi

UBUNTU_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
info "Ubuntu ${UBUNTU_VER} detected."

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/whisper-note"
VENV_DIR="$INSTALL_DIR/venv"
CONF_DIR="$HOME/.config/whisper-note"
ENV_FILE="$CONF_DIR/env"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/whisper-note.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo -e "${B}╔══════════════════════════════════════════════╗${X}"
echo -e "${B}║       Whisper Note — Installer               ║${X}"
echo -e "${B}║       by Himangshu Pan                       ║${X}"
echo -e "${B}╚══════════════════════════════════════════════╝${X}"
echo

# ── System dependencies ───────────────────────────────────────────────────────
info "Installing system packages (requires sudo)…"
sudo apt-get update -qq
sudo apt-get install -y \
    python3-venv python3-dev \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1 \
    xdotool \
    >/dev/null 2>&1
ok "System packages installed."

# ── Gather user configuration ─────────────────────────────────────────────────
echo
echo -e "${W}── Whisper (Speech-to-Text) ──────────────────────────────${X}"
WHISPER_MODEL=$(ask    "Whisper model  (tiny/base/small/medium/large-v3)" "base")
WHISPER_COMPUTE=$(ask  "Compute type   (int8/float16/float32)"            "int8")
VOICE_NOTES=$(ask      "Notes directory"                                  "$HOME/VoiceNotes")

echo
echo -e "${W}── LLM Formatter ─────────────────────────────────────────${X}"
echo -e "   ${Y}Presets${X}:"
echo -e "     Ollama (local)  →  URL: http://127.0.0.1:11434/v1  KEY: ollama"
echo -e "     OpenAI          →  URL: https://api.openai.com/v1"
echo -e "     Claude          →  URL: https://api.anthropic.com/v1"
echo
WN_LLM_URL=$(ask     "LLM API URL"    "http://127.0.0.1:11434/v1")
WN_LLM_KEY=$(ask_secret "LLM API key (hidden)")
if [[ -z "$WN_LLM_KEY" ]]; then WN_LLM_KEY="ollama"; fi
WN_LLM_MODEL=$(ask   "LLM model name" "qwen3:4b")
WN_LLM_TIMEOUT=$(ask "Request timeout (seconds)" "300")

echo
echo -e "${W}── Summary ───────────────────────────────────────────────${X}"
echo -e "   Whisper model    : ${G}${WHISPER_MODEL}${X} (${WHISPER_COMPUTE})"
echo -e "   Notes directory  : ${G}${VOICE_NOTES}${X}"
echo -e "   LLM URL          : ${G}${WN_LLM_URL}${X}"
echo -e "   LLM model        : ${G}${WN_LLM_MODEL}${X}"
echo -e "   Install path     : ${G}${INSTALL_DIR}${X}"
echo
echo -en "${W}  Proceed with installation?${X} [${Y}Y/n${X}]: "
read -r _confirm
[[ "${_confirm,,}" == "n" ]] && { echo "Aborted."; exit 0; }

# ── Virtual environment ───────────────────────────────────────────────────────
info "Creating virtual environment at ${VENV_DIR}…"
mkdir -p "$INSTALL_DIR"
python3 -m venv --system-site-packages "$VENV_DIR"
ok "Virtual environment created."

info "Installing whisper-note from PyPI…"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet whisper-note
ok "whisper-note installed ($(\"$VENV_DIR/bin/whisper-note\" --version))."

# ── Environment file ──────────────────────────────────────────────────────────
info "Writing environment file to ${ENV_FILE}…"
mkdir -p "$CONF_DIR"
cat > "$ENV_FILE" << ENVEOF
# Whisper Note — environment configuration
# Edit with:  whisper-note config set KEY=VALUE
# Then restart the service for changes to take effect.

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
chmod 600 "$ENV_FILE"   # protect API key
ok "Environment file written (permissions: 600)."

# ── Systemd user service ──────────────────────────────────────────────────────
info "Installing systemd user service…"
mkdir -p "$SERVICE_DIR"
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

systemctl --user daemon-reload
systemctl --user enable whisper-note
systemctl --user start  whisper-note
ok "Service enabled and started."

# ── Desktop entry ─────────────────────────────────────────────────────────────
info "Registering desktop entry…"
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
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
ok "Desktop entry registered."

# ── Done ─────────────────────────────────────────────────────────────────────
echo
echo -e "${G}╔══════════════════════════════════════════════╗${X}"
echo -e "${G}║   Installation complete!                     ║${X}"
echo -e "${G}╚══════════════════════════════════════════════╝${X}"
echo
echo -e "  The widget is now running in the top-right corner of your screen."
echo
echo -e "  ${W}Usage${X}"
echo -e "    ${Y}Hold${X} Ctrl+Alt+Space   Start recording"
echo -e "    ${Y}Release any key${X}       Stop & transcribe"
echo -e "    ${Y}Esc${X}                   Quit"
echo
echo -e "  ${W}Service commands${X}"
echo -e "    systemctl --user start   whisper-note"
echo -e "    systemctl --user stop    whisper-note"
echo -e "    systemctl --user restart whisper-note"
echo -e "    journalctl --user -u whisper-note -f"
echo
echo -e "  ${W}Change configuration${X}"
echo -e "    ${VENV_DIR}/bin/whisper-note config show"
echo -e "    ${VENV_DIR}/bin/whisper-note config set WN_LLM_MODEL=gpt-4o-mini"
echo -e "    ${VENV_DIR}/bin/whisper-note config set WHISPER_MODEL=small"
echo
