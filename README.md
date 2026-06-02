# whisper-note

> Hold **Ctrl+Alt+Space** to record your voice. Release to get a formatted markdown note.

[![PyPI version](https://img.shields.io/pypi/v/whisper-note)](https://pypi.org/project/whisper-note/)
[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20Linux-orange)](https://ubuntu.com/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**whisper-note** is an Ubuntu desktop tool that turns spoken voice into clean, structured markdown notes:

- **Local transcription** via [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — no cloud, no latency
- **AI formatting** via any OpenAI-compatible LLM — Ollama (local), OpenAI, or Claude
- **Always-on-top widget** — shows live status with a colour-coded accent bar
- **Runs as a systemd user service** — starts automatically on login
- **Reliability first** — raw transcript is saved before any AI call; failed audio is preserved

---

## Table of Contents

- [How it works](#how-it-works)
- [Installation](#installation)
  - [End users — one-command installer](#end-users--one-command-installer)
  - [Developers — pip install](#developers--pip-install)
- [Configuration](#configuration)
  - [Environment variables](#environment-variables)
  - [Changing config after install](#changing-config-after-install)
  - [Whisper models](#whisper-models)
  - [LLM providers](#llm-providers)
- [Usage](#usage)
- [Status widget](#status-widget)
- [Service management](#service-management)
- [Output structure](#output-structure)
- [Troubleshooting](#troubleshooting)
- [Developer guide](#developer-guide)
- [License](#license)

---

## How it works

```
Hold Ctrl+Alt+Space  →  Widget turns RED  →  Recording starts
Speak your note
Release any key      →  Widget turns AMBER →  Processing:
                          1. Audio written to temp WAV
                          2. Whisper transcribes locally (offline)
                          3. Raw transcript saved to raw/
                          4. LLM formats it into clean markdown
                          5. Markdown note saved
                          6. Temp WAV deleted
Widget turns GREEN   →  Note saved  →  Returns to IDLE after a few seconds
```

If the LLM is unavailable, the raw transcript is still saved.  
If Whisper fails, the WAV is moved to `failed_audio/` for manual recovery.

---

## Installation

### End users — one-command installer

The installer handles everything: system packages, virtual environment, configuration prompts, environment file, systemd service, and desktop entry. **No manual steps required.**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0xSh3ru/whisper-note/main/install.sh)
```

Or download and inspect first:

```bash
curl -O https://raw.githubusercontent.com/0xSh3ru/whisper-note/main/install.sh
cat install.sh          # review before running
bash install.sh
```

The installer will ask you:

| Prompt | Default | Description |
|---|---|---|
| Whisper model | `base` | Speech-to-text accuracy vs speed |
| Compute type | `int8` | Inference precision |
| Notes directory | `~/VoiceNotes` | Where markdown notes are saved |
| LLM API URL | `http://127.0.0.1:11434/v1` | Ollama, OpenAI, or Claude endpoint |
| LLM API key | *(hidden)* | Leave blank for local Ollama |
| LLM model name | `qwen3:4b` | Model to use for formatting |
| Request timeout | `300` | Seconds (increase for slow CPU inference) |

After the installer completes, the widget appears in the top-right corner of your screen and the service starts automatically on every login.

---

### Developers — pip install

`pip install` gives you the CLI only. System packages and service setup are your responsibility.

**Requirements:**

```bash
sudo apt install \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1
```

**Install** (venv must use `--system-site-packages` for GTK3):

```bash
python3 -m venv --system-site-packages .venv
.venv/bin/pip install whisper-note
```

**Run:**

```bash
DISPLAY=:0 GDK_BACKEND=x11 \
  WN_LLM_URL=http://127.0.0.1:11434/v1 \
  WN_LLM_MODEL=qwen3:4b \
  WHISPER_MODEL=base \
  .venv/bin/whisper-note
```

**From source:**

```bash
git clone https://github.com/0xSh3ru/whisper-note.git
cd whisper-note
python3 -m venv --system-site-packages .venv
.venv/bin/pip install -e ".[dev]"
```

> **Why `--system-site-packages`?**  
> `python3-gi` (GTK3 Python bindings) is an apt package — it cannot be
> installed with pip. This flag lets the venv see it from the system.

---

## Configuration

### Environment variables

All settings are driven by environment variables. When installed via `install.sh`, these are written to `~/.config/whisper-note/env` and loaded by the systemd service automatically.

#### Speech-to-text

| Variable | Default | Description |
|---|---|---|
| `WHISPER_MODEL` | `base` | Model name (`tiny`/`base`/`small`/`medium`/`large-v3`) or path to local model |
| `WHISPER_COMPUTE_TYPE` | `int8` | Inference precision: `int8` / `float16` / `float32` |

#### Notes output

| Variable | Default | Description |
|---|---|---|
| `VOICE_NOTES_DIR` | `~/VoiceNotes` | Directory where markdown notes are saved |
| `WHISPER_LOG_DIR` | `~/.local/share/whisper-note/logs` | Session log directory |

#### LLM formatter

Works with any OpenAI-compatible API endpoint — Ollama, OpenAI, and Claude are all supported with the same variables.

| Variable | Default | Description |
|---|---|---|
| `WN_LLM_URL` | `http://127.0.0.1:11434/v1` | API base URL |
| `WN_LLM_KEY` | `ollama` | API key (use any non-empty string for local Ollama) |
| `WN_LLM_MODEL` | `qwen3:4b` | Model name |
| `WN_LLM_TIMEOUT` | `300` | Request timeout in seconds |

#### Display

| Variable | Default | Description |
|---|---|---|
| `GDK_BACKEND` | *(unset)* | Set to `x11` on GNOME Wayland for reliable always-on-top |

---

### Changing config after install

Use the built-in CLI subcommand — no need to edit files manually:

```bash
# Show current configuration
whisper-note config show

# Change the LLM model
whisper-note config set WN_LLM_MODEL=gpt-4o-mini

# Switch to OpenAI
whisper-note config set WN_LLM_URL=https://api.openai.com/v1
whisper-note config set WN_LLM_KEY=sk-...
whisper-note config set WN_LLM_MODEL=gpt-4o-mini

# Switch to Claude
whisper-note config set WN_LLM_URL=https://api.anthropic.com/v1
whisper-note config set WN_LLM_KEY=sk-ant-...
whisper-note config set WN_LLM_MODEL=claude-haiku-4-5-20251001

# Use a better Whisper model
whisper-note config set WHISPER_MODEL=small

# Restart the service to apply changes
systemctl --user restart whisper-note
```

Changes are written to `~/.config/whisper-note/env` and the service is restarted automatically.

---

### Whisper models

Models are downloaded on first use and cached in `~/.cache/huggingface/hub/`.

| Model | Download | Speed | Accuracy | Recommended for |
|---|---|---|---|---|
| `tiny` | ~39 MB | Fastest | Basic | Testing / weak hardware |
| `base` | ~74 MB | Fast | Good | **Default — daily use** |
| `small` | ~244 MB | Moderate | Better | Higher accuracy |
| `medium` | ~769 MB | Slow | High | Technical content |
| `large-v3` | ~1.5 GB | Slowest | Best | Maximum accuracy |

---

### LLM providers

All three providers use the same four `WN_LLM_*` variables:

```bash
# Ollama (local — default)
WN_LLM_URL=http://127.0.0.1:11434/v1
WN_LLM_KEY=ollama
WN_LLM_MODEL=qwen3:4b

# OpenAI
WN_LLM_URL=https://api.openai.com/v1
WN_LLM_KEY=sk-...
WN_LLM_MODEL=gpt-4o-mini

# Claude (Anthropic)
WN_LLM_URL=https://api.anthropic.com/v1
WN_LLM_KEY=sk-ant-...
WN_LLM_MODEL=claude-haiku-4-5-20251001
```

If the LLM is unavailable or times out, notes are still saved as raw transcripts — no speech is ever lost.

---

## Usage

| Action | Result |
|---|---|
| **Hold** `Ctrl+Alt+Space` | Recording starts (widget turns red) |
| **Release** any of the three keys | Recording stops and processing begins |
| **Esc** | Quit whisper-note |

Tip: you only need to hold the combination long enough to speak. Release as soon as you finish.

---

## Status widget

A floating widget sits in the top-right corner of your screen. Drag it anywhere with a left-click.

| Accent colour | State | Hint shown |
|---|---|---|
| Indigo | **IDLE** | Press & hold `Ctrl+Alt+Space` to record |
| Red | **RECORDING** | Release any key to stop |
| Amber | **PROCESSING** | Transcribing audio… |
| Green | **COMPLETED** | Note saved! |
| Flashing red | **ERROR** | Check log for details |

The widget always shows the tool name, current state, and a contextual hint so you always know what to do next.

---

## Service management

whisper-note runs as a **systemd user service** that starts automatically on login.

```bash
# Start / stop / restart
systemctl --user start   whisper-note
systemctl --user stop    whisper-note
systemctl --user restart whisper-note

# Check status
systemctl --user status whisper-note

# Follow live logs
journalctl --user -u whisper-note -f

# Disable auto-start on login
systemctl --user disable whisper-note
```

---

## Output structure

```
~/VoiceNotes/
├── 20260602_143022.md          ← AI-formatted markdown note
├── 20260602_150011.md
├── raw/
│   ├── 20260602_143022.txt     ← raw transcript (saved before AI call)
│   └── 20260602_150011.txt
└── failed_audio/
    └── 20260602_160300.wav     ← audio preserved here if Whisper fails
```

---

## Troubleshooting

### Widget does not appear

GTK3 bindings are missing or invisible to the venv:

```bash
# Install system packages
sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0

# Recreate venv with system package access
python3 -m venv --system-site-packages .venv
.venv/bin/pip install whisper-note
```

### Hotkey not triggering recording

whisper-note requires XWayland (X11 keyboard capture) on GNOME Wayland. Launch with:

```bash
DISPLAY=:0 GDK_BACKEND=x11 whisper-note
```

The service file set by `install.sh` includes this automatically.

### LLM formatting times out

Ollama running on CPU (no GPU) is slow. Increase the timeout:

```bash
whisper-note config set WN_LLM_TIMEOUT=600
```

Or switch to a faster cloud provider:

```bash
whisper-note config set WN_LLM_URL=https://api.openai.com/v1
whisper-note config set WN_LLM_KEY=sk-...
whisper-note config set WN_LLM_MODEL=gpt-4o-mini
```

### No audio input detected

```bash
arecord -l        # list capture devices
```

Install audio libraries if missing:

```bash
sudo apt install portaudio19-dev libsndfile1
```

### Checking logs

```bash
# Live service logs
journalctl --user -u whisper-note -f

# Session log files
ls ~/.local/share/whisper-note/logs/
```

---

## Developer guide

### Project layout

```
src/whisper_note/
├── __init__.py        Package version (reads from installed metadata)
├── cli.py             Entry point — arg parsing, config init, preflight, launch
├── config.py          Config dataclass + singleton (env-var defaults)
├── config_manager.py  Read/write ~/.config/whisper-note/env (config CLI)
├── preflight.py       Startup checks — Python, platform, GTK, audio, LLM
├── log.py             Session logging (file + console)
├── storage.py         Atomic file writes, directory management
├── recorder.py        Thread-safe sounddevice audio capture
├── transcriber.py     faster-whisper wrapper (loaded once at startup)
├── formatter.py       Generic LLM formatter (OpenAI-compatible) + raw fallback
├── indicator.py       GTK3 floating status widget (console fallback if absent)
└── main.py            Orchestration — hotkey listener + pipeline threads
```

### Architecture

```
Environment file (~/.config/whisper-note/env)
        │
        ▼
config.Config()          env-var defaults → CLI flag overrides → singleton
        │
        ▼
preflight.run_checks()   validates Python, GTK, audio, LLM endpoint
        │
        ▼
main.main()
  ├── GTK main loop (main thread)
  ├── pynput keyboard listener (daemon thread)
  │     Hold Ctrl+Alt+Space → recorder.start()
  │     Release → recorder.stop() → pipeline thread
  └── Pipeline thread (per recording)
        ├── Whisper transcribe (local)
        ├── Save raw transcript
        ├── LLM format (generic OpenAI-compatible client)
        └── Save markdown note
```

### Reliability guarantees

| Priority | Guarantee | How |
|---|---|---|
| 1 | Speech never lost | Raw transcript saved before LLM call |
| 2 | Whisper failure safe | WAV moved to `failed_audio/` |
| 3 | LLM failure safe | Fallback markdown wraps raw transcript |
| 4 | Atomic file writes | `tempfile` + `os.replace()` — no partial files |

### Running tests

```bash
.venv/bin/pytest
```

### Linting

```bash
.venv/bin/ruff check src/
.venv/bin/black src/
```

### Releasing a new version

1. Bump `version` in `pyproject.toml`
2. Commit: `git commit -m "Bump version to X.Y.Z"`
3. Build: `python -m build`
4. Upload to TestPyPI: `twine upload --repository-url https://test.pypi.org/legacy/ dist/*`
5. Verify: `pip install --index-url https://test.pypi.org/simple/ whisper-note==X.Y.Z`
6. Upload to PyPI: `twine upload dist/*`

---

## License

[MIT](LICENSE) © [Himangshu Pan](https://github.com/0xSh3ru)
