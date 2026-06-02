#!/usr/bin/env bash
# =============================================================================
#  Whisper Note — Interactive Installer  (Ubuntu only)
#  Shows every command and its live output so you always know what's happening.
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; Y='\033[0;33m'; G='\033[0;32m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1m'; D='\033[2m'; X='\033[0m'

# ── Progress counter ──────────────────────────────────────────────────────────
TOTAL_STEPS=7
STEP=0

step() {
    STEP=$(( STEP + 1 ))
    echo
    echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${X}"
    echo -e "${B}  [${STEP}/${TOTAL_STEPS}]  ${W}${1}${X}"
    echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${X}"
}

# Print the command in dim cyan before running it
run() {
    echo -e "\n${D}${C}  \$ $*${X}"
    "$@"
}

ok()   { echo -e "\n${G}  ✓  ${1}${X}"; }
warn() { echo -e "${Y}  ⚠  ${1}${X}"; }
die()  { echo -e "\n${R}  ✗  ${1}${X}" >&2; exit 1; }

ask() {
    echo -en "\n${W}  ${1}${X}  ${D}[default: ${Y}${2}${D}]${X}: "
    read -r _ans
    echo "${_ans:-$2}"
}

ask_secret() {
    echo -en "\n${W}  ${1}${X}  ${D}[hidden — leave blank to skip]${X}: "
    read -rs _sec
    echo
    echo "$_sec"
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${B}"
echo -e "  ╔══════════════════════════════════════════════════════╗"
echo -e "  ║                                                      ║"
echo -e "  ║   🎙  Whisper Note — Installer                       ║"
echo -e "  ║       Voice-to-Markdown Note Taker for Ubuntu        ║"
echo -e "  ║                                                      ║"
echo -e "  ║       by Himangshu Pan  •  github.com/0xSh3ru       ║"
echo -e "  ║                                                      ║"
echo -e "  ╚══════════════════════════════════════════════════════╝"
echo -e "${X}"
echo -e "  This installer will:"
echo -e "    ${G}1.${X} Install required system packages  (apt)"
echo -e "    ${G}2.${X} Ask for your configuration"
echo -e "    ${G}3.${X} Create a dedicated Python virtual environment"
echo -e "    ${G}4.${X} Install whisper-note from PyPI"
echo -e "    ${G}5.${X} Write your settings to ${C}~/.config/whisper-note/env${X}"
echo -e "    ${G}6.${X} Register and start the systemd user service"
echo -e "    ${G}7.${X} Register the desktop entry"
echo

# ── Ubuntu guard ──────────────────────────────────────────────────────────────
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
OS_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "")
UBUNTU_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")

if [[ "$OS_ID" != "ubuntu" && "$OS_LIKE" != *"ubuntu"* ]]; then
    die "This installer requires Ubuntu (detected: ${OS_ID:-unknown})."
fi
echo -e "  ${G}✓${X}  Ubuntu ${UBUNTU_VER} detected."

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/whisper-note"
VENV_DIR="$INSTALL_DIR/venv"
CONF_DIR="$HOME/.config/whisper-note"
ENV_FILE="$CONF_DIR/env"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/whisper-note.service"

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 1 — System packages
# ═════════════════════════════════════════════════════════════════════════════
step "Install required system packages"

echo -e "  ${D}Packages:${X}"
echo -e "    ${C}python3-venv python3-dev${X}          Python virtual environment"
echo -e "    ${C}python3-gi python3-gi-cairo${X}       GTK3 Python bindings"
echo -e "    ${C}gir1.2-gtk-3.0${X}                   GTK3 GObject introspection"
echo -e "    ${C}portaudio19-dev libsndfile1${X}       Audio capture libraries"
echo -e "    ${C}xdotool${X}                           X11 input automation"
echo

echo -e "  ${Y}⚠  sudo is required for apt — you may be prompted for your password.${X}"

run sudo apt-get update

run sudo apt-get install -y \
    python3-venv python3-dev \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1 \
    xdotool

ok "All system packages installed."

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Gather configuration
# ═════════════════════════════════════════════════════════════════════════════
step "Configure whisper-note"

echo -e "  ${W}── Speech-to-Text (Whisper) ──────────────────────────────────────${X}"
echo -e "  ${D}Models: tiny (fastest/least accurate) → large-v3 (slowest/best)${X}"
WHISPER_MODEL=$(ask  "Whisper model  (tiny / base / small / medium / large-v3)" "base")
WHISPER_COMPUTE=$(ask "Compute type  (int8 = fastest on CPU)"                   "int8")
VOICE_NOTES=$(ask    "Notes output directory"                                   "$HOME/VoiceNotes")

echo
echo -e "  ${W}── LLM Formatter ────────────────────────────────────────────────${X}"
echo -e "  ${D}Presets (copy-paste the URL and key below):${X}"
echo -e "    ${C}Ollama (local)  ${X}URL: http://127.0.0.1:11434/v1   KEY: ollama"
echo -e "    ${C}OpenAI          ${X}URL: https://api.openai.com/v1    KEY: sk-..."
echo -e "    ${C}Claude          ${X}URL: https://api.anthropic.com/v1 KEY: sk-ant-..."

WN_LLM_URL=$(ask "LLM API URL"                             "http://127.0.0.1:11434/v1")
WN_LLM_KEY=$(ask_secret "LLM API key")
[[ -z "$WN_LLM_KEY" ]] && WN_LLM_KEY="ollama"
WN_LLM_MODEL=$(ask   "LLM model name"                     "qwen3:4b")
WN_LLM_TIMEOUT=$(ask "LLM request timeout (seconds)"      "300")

echo
echo -e "  ${W}── Summary ──────────────────────────────────────────────────────${X}"
echo -e "   Whisper model    : ${G}${WHISPER_MODEL}${X} (${WHISPER_COMPUTE})"
echo -e "   Notes directory  : ${G}${VOICE_NOTES}${X}"
echo -e "   LLM URL          : ${G}${WN_LLM_URL}${X}"
echo -e "   LLM model        : ${G}${WN_LLM_MODEL}${X}"
echo -e "   Install path     : ${G}${INSTALL_DIR}${X}"
echo
echo -en "  ${W}Proceed with installation?${X}  [${Y}Y/n${X}]: "
read -r _confirm
[[ "${_confirm,,}" == "n" ]] && { echo -e "\n  Aborted."; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Virtual environment
# ═════════════════════════════════════════════════════════════════════════════
step "Create dedicated Python virtual environment"

echo -e "  ${D}Location: ${VENV_DIR}${X}"
echo -e "  ${D}Using --system-site-packages so GTK3 (python3-gi) is visible.${X}"

run mkdir -p "$INSTALL_DIR"
run python3 -m venv --system-site-packages "$VENV_DIR"

echo
echo -e "  ${D}Verifying GTK3 is accessible inside the venv…${X}"
"$VENV_DIR/bin/python3" -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk; print('  GTK3 OK — version', Gtk.get_major_version(), Gtk.get_minor_version())"

ok "Virtual environment ready."

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Install whisper-note
# ═════════════════════════════════════════════════════════════════════════════
step "Install whisper-note from PyPI"

echo -e "  ${D}This will download whisper-note and all Python dependencies.${X}"
echo -e "  ${D}faster-whisper, openai, httpx, sounddevice, pynput, …${X}"
echo

run "$VENV_DIR/bin/pip" install --upgrade pip
echo
run "$VENV_DIR/bin/pip" install whisper-note

VER=$("$VENV_DIR/bin/whisper-note" --version 2>/dev/null || echo "unknown")
ok "whisper-note ${VER} installed."

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Write environment file
# ═════════════════════════════════════════════════════════════════════════════
step "Write environment configuration file"

echo -e "  ${D}Location: ${ENV_FILE}${X}"
echo -e "  ${D}Permissions will be set to 600 (owner read/write only) to protect your API key.${X}"

run mkdir -p "$CONF_DIR"

cat > "$ENV_FILE" << ENVEOF
# Whisper Note — environment configuration
# ─────────────────────────────────────────
# Edit interactively:  whisper-note config set KEY=VALUE
# View current values: whisper-note config show
# Apply changes:       systemctl --user restart whisper-note

GDK_BACKEND=x11

# ── Whisper (speech-to-text) ──────────────────────────────────────────────────
WHISPER_MODEL=${WHISPER_MODEL}
WHISPER_COMPUTE_TYPE=${WHISPER_COMPUTE}

# ── Notes output ──────────────────────────────────────────────────────────────
VOICE_NOTES_DIR=${VOICE_NOTES}

# ── LLM formatter (OpenAI-compatible — works with Ollama / OpenAI / Claude) ──
WN_LLM_URL=${WN_LLM_URL}
WN_LLM_KEY=${WN_LLM_KEY}
WN_LLM_MODEL=${WN_LLM_MODEL}
WN_LLM_TIMEOUT=${WN_LLM_TIMEOUT}
ENVEOF

chmod 600 "$ENV_FILE"
echo -e "  ${D}Contents:${X}"
grep -v "WN_LLM_KEY" "$ENV_FILE" | grep -v "^#" | grep -v "^$" | \
    sed 's/^/    /'
echo -e "    ${D}WN_LLM_KEY=<hidden>${X}"

ok "Environment file written."

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Systemd user service
# ═════════════════════════════════════════════════════════════════════════════
step "Register and start systemd user service"

echo -e "  ${D}Service file: ${SERVICE_FILE}${X}"
echo -e "  ${D}The service reads settings from: ${ENV_FILE}${X}"

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

echo -e "\n${D}  \$ systemctl --user daemon-reload${X}"
systemctl --user daemon-reload

echo -e "${D}  \$ systemctl --user enable whisper-note${X}"
systemctl --user enable whisper-note

echo -e "${D}  \$ systemctl --user start whisper-note${X}"
systemctl --user start whisper-note

sleep 2
echo
echo -e "  ${D}Service status:${X}"
systemctl --user status whisper-note --no-pager | sed 's/^/    /'

ok "Service enabled and running — starts automatically on login."

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 7 — Desktop entry
# ═════════════════════════════════════════════════════════════════════════════
step "Register desktop entry"

APPS_DIR="$HOME/.local/share/applications"
echo -e "  ${D}Location: ${APPS_DIR}/whisper-note.desktop${X}"

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

ok "Desktop entry registered."

# ═════════════════════════════════════════════════════════════════════════════
#  Done
# ═════════════════════════════════════════════════════════════════════════════
echo
echo -e "${G}"
echo -e "  ╔══════════════════════════════════════════════════════╗"
echo -e "  ║                                                      ║"
echo -e "  ║   ✓  Installation complete!                         ║"
echo -e "  ║                                                      ║"
echo -e "  ╚══════════════════════════════════════════════════════╝"
echo -e "${X}"
echo -e "  The ${W}Whisper Note${X} widget is now running in the ${W}top-right corner${X}"
echo -e "  of your screen.  It will start automatically on every login."
echo
echo -e "  ${W}How to use${X}"
echo -e "    ${Y}Hold${X}  Ctrl+Alt+Space   →  Recording starts  (widget turns red)"
echo -e "    ${Y}Release${X} any key         →  Transcribing…     (widget turns amber)"
echo -e "    ${Y}Done${X}                    →  Note saved!       (widget turns green)"
echo -e "    ${Y}Esc${X}                     →  Quit"
echo
echo -e "  ${W}Notes saved to${X}  ${C}${VOICE_NOTES}${X}"
echo
echo -e "  ${W}Service commands${X}"
echo -e "    ${C}systemctl --user start   whisper-note${X}"
echo -e "    ${C}systemctl --user stop    whisper-note${X}"
echo -e "    ${C}systemctl --user restart whisper-note${X}"
echo -e "    ${C}journalctl --user -u whisper-note -f${X}   (live logs)"
echo
echo -e "  ${W}Change configuration${X}"
echo -e "    ${C}whisper-note config show${X}"
echo -e "    ${C}whisper-note config set WN_LLM_MODEL=gpt-4o-mini${X}"
echo -e "    ${C}whisper-note config set WHISPER_MODEL=small${X}"
echo
