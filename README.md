# whisper-note

> Hold **Ctrl+Space** to record your voice, release to get a formatted markdown note.

**whisper-note** is a Linux desktop tool that converts spoken voice into structured markdown notes using [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for offline transcription and the OpenAI API for intelligent formatting.

- No cloud required for transcription — Whisper runs locally
- OpenAI formatting is optional — notes are always saved even without an API key
- Reliability first — raw transcript is saved before any AI call, failed audio is preserved

---

## Table of Contents

- [How it works](#how-it-works)
- [Quick Start](#quick-start-end-users)
- [Configuration](#configuration)
- [Output structure](#output-structure)
- [Status window](#status-window)
- [Developer guide](#developer-guide)
- [Publishing to PyPI](#publishing-to-pypi)
- [License](#license)

---

## How it works

```
Hold Ctrl+Space  →  recording starts (status: red RECORDING)
Speak your note
Release Ctrl+Space  →  processing starts (status: amber PROCESSING)
  1. Audio written to temp WAV
  2. Whisper transcribes locally (English, no cloud)
  3. Raw transcript saved immediately to raw/
  4. OpenAI formats it into clean markdown (or fallback if no key)
  5. Markdown note saved to notes dir
  6. Temp WAV deleted
Status: green COMPLETED  →  back to grey IDLE after a few seconds
```

Even if step 4 fails, the raw transcript from step 3 is always on disk.  
Even if step 2 fails, the WAV is moved to `failed_audio/` for manual recovery.

---

## Quick Start (End Users)

### 1. System dependencies

```bash
sudo apt update
sudo apt install \
    python3 python3-pip python3-venv \
    python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
    portaudio19-dev libsndfile1
```

Optional — for desktop pop-up notifications on error:

```bash
sudo apt install libnotify-bin
```

### 2. Install whisper-note

**From PyPI** (recommended):

```bash
pip install whisper-note
```

**From source**:

```bash
git clone https://github.com/YOUR_USERNAME/whisper-note.git
cd whisper-note
pip install .
```

### 3. Link GTK3 bindings into your environment

GTK3 Python bindings are system packages and cannot be installed via pip.  
Run this **once** after installing into a virtual environment:

```bash
# Replace python3.X with your actual version (python3.10 / python3.12 etc.)
echo "/usr/lib/python3/dist-packages" \
  >> "$(python -c 'import site; print(site.getsitepackages()[0])')/system-gi.pth"
```

If you installed system-wide with `pip install --user`, skip this step — the
system packages are already visible.

### 4. Set your OpenAI API key

```bash
export OPENAI_API_KEY=sk-...
```

To make it permanent, add to your shell profile:

```bash
echo 'export OPENAI_API_KEY=sk-...' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
```

> **No OpenAI key?**  
> whisper-note still works. Notes are saved with the raw transcript wrapped in
> minimal markdown. You can set the key later and run again.

### 5. Run

```bash
# Recommended on Ubuntu 24.04 (GNOME + Wayland) for reliable always-on-top:
GDK_BACKEND=x11 whisper-note

# On X11 or if you don't need the status window always on top:
whisper-note
```

whisper-note will:

1. Run a startup check and report any problems
2. Download the Whisper `base` model on first run (~74 MB, cached after that)
3. Show a small status window in the top-right corner
4. Wait for **Ctrl+Space**

**Controls:**

| Action | Result |
|---|---|
| Hold **Ctrl+Space** | Start recording |
| Release **Ctrl+Space** | Stop and process |
| **Esc** | Quit |

---

## Configuration

All settings are controlled by **environment variables**.  
**CLI flags override** environment variables when both are set.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `VOICE_NOTES_DIR` | `~/VoiceNotes` | Where to save notes |
| `OPENAI_API_KEY` | *(none)* | OpenAI API key (optional — see above) |
| `OPENAI_MODEL` | `gpt-4o-mini` | OpenAI chat model for formatting |
| `WHISPER_MODEL` | `base` | Whisper model name **or** path to a local model dir |
| `WHISPER_COMPUTE_TYPE` | `int8` | Inference precision: `int8` / `float16` / `float32` |
| `WHISPER_LOG_DIR` | `~/.local/share/whisper-note/logs` | Session log directory |

### CLI flags

```
whisper-note [options]

  --notes-dir DIR       Override VOICE_NOTES_DIR
  --model MODEL         Override WHISPER_MODEL
  --compute-type TYPE   Override WHISPER_COMPUTE_TYPE  (int8 / float16 / float32)
  --openai-model MODEL  Override OPENAI_MODEL
  --log-dir DIR         Override WHISPER_LOG_DIR
  --skip-checks         Skip startup dependency checks (not recommended)
  --version             Print version and exit
  -h, --help            Print this help and exit
```

### Whisper models

Named models are downloaded automatically on first use and cached in
`~/.cache/huggingface/hub/`.

| Name | Download size | Speed | Accuracy |
|---|---|---|---|
| `tiny` | ~39 MB | Fastest | Lower |
| `base` | ~74 MB | Fast | Good **(default)** |
| `small` | ~244 MB | Moderate | Better |
| `medium` | ~769 MB | Slow | High |
| `large-v3` | ~1.5 GB | Slowest | Best |

Use a local model:

```bash
whisper-note --model /path/to/your/model
# or
export WHISPER_MODEL=/path/to/your/model
```

### Example: custom setup

```bash
export VOICE_NOTES_DIR=~/Documents/research-notes
export WHISPER_MODEL=small
export OPENAI_API_KEY=sk-...
GDK_BACKEND=x11 whisper-note --log-dir ~/logs/whisper
```

---

## Output structure

```
~/VoiceNotes/
├── WHISPER_20260602_143022.md         ← formatted note (OpenAI or fallback)
├── WHISPER_20260602_150011.md
├── raw/
│   ├── RAW_WHISPER_20260602_143022.txt   ← raw transcript, saved before AI call
│   └── RAW_WHISPER_20260602_150011.txt
├── failed_audio/
│   └── VOICE_20260602_160300.wav         ← audio saved here if Whisper fails
└── archive/                              ← for your own organisation
```

**File naming:**

| Pattern | Contents |
|---|---|
| `WHISPER_<timestamp>.md` | Formatted markdown note |
| `raw/RAW_WHISPER_<timestamp>.txt` | Verbatim transcript |
| `failed_audio/VOICE_<timestamp>.wav` | Audio when transcription fails |

---

## Status window

A small floating window appears in the top-right corner:

| Colour | State | Meaning |
|---|---|---|
| Grey | **IDLE** | Ready to record |
| Red | **RECORDING** | Actively capturing audio |
| Amber | **PROCESSING** | Transcribing / formatting |
| Green | **COMPLETED** | Note saved successfully |
| Flashing red | **ERROR** | See terminal or log file |

### Wayland note

GTK `set_keep_above` is a compositor hint and may be ignored on native GNOME
Wayland. For a guaranteed always-on-top window, launch with `GDK_BACKEND=x11`
to run under XWayland (fully supported on Ubuntu 24.04):

```bash
GDK_BACKEND=x11 whisper-note
```

---

## Logs

Each session writes a timestamped log file:

```
~/.local/share/whisper-note/logs/whisper_20260602_143000.log
```

Override the directory:

```bash
export WHISPER_LOG_DIR=/var/log/whisper   # requires write permission
```

---

## Developer guide

### Setup

```bash
git clone https://github.com/YOUR_USERNAME/whisper-note.git
cd whisper-note

python3 -m venv .venv
source .venv/bin/activate

# Link system GTK3 bindings (one-time):
echo "/usr/lib/python3/dist-packages" \
  > .venv/lib/python3.$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/site-packages/system-gi.pth

# Install in editable mode with dev extras:
pip install -e ".[dev]"
```

### Project layout

```
whisper_note/
├── cli.py          Entry point — arg parsing, config init, preflight, launch
├── config.py       Config dataclass + singleton (env-var defaults)
├── preflight.py    Startup checks — deps, audio, dirs, model, API key
├── log.py          Session logging (file + console)
├── storage.py      Atomic file writes, directory management
├── recorder.py     Thread-safe sounddevice audio capture
├── transcriber.py  faster-whisper wrapper (English, loaded once at startup)
├── formatter.py    OpenAI formatting + plain-text fallback
├── indicator.py    GTK3 floating status window (console fallback if unavailable)
└── main.py         Orchestration — hotkey listener + pipeline threads
```

### Configuration flow

```
Environment variables
        ↓
  config.Config()         (env-var defaults)
        ↓
  CLI arg overrides       (cli.py applies --flags)
        ↓
  config.init(cfg)        (singleton registered)
        ↓
  preflight.run_checks()  (validates everything)
        ↓
  main.main()             (modules read config.get() lazily)
```

### Reliability contract

| Priority | Guarantee | Implementation |
|---|---|---|
| 1 | Speech never lost | Raw transcript saved before OpenAI call |
| 2 | Whisper failure safe | WAV moved to `failed_audio/` |
| 3 | OpenAI failure safe | Fallback markdown wraps raw transcript |
| 4 | Atomic writes | `tempfile + os.replace()` — no partial files |
| 5 | Config always resolved | `config.get()` initialises with defaults if needed |

### Running tests

```bash
pytest
```

### Linting and formatting

```bash
ruff check whisper_note/
black whisper_note/
```

---

## Publishing to PyPI

> Before publishing, verify the package name `whisper-note` is available:
> https://pypi.org/project/whisper-note/

Update `YOUR_USERNAME` in `pyproject.toml` → `[project.urls]`, then:

```bash
pip install build twine

# Build
python -m build

# Test on TestPyPI first (recommended)
twine upload --repository testpypi dist/*
pip install --index-url https://test.pypi.org/simple/ whisper-note

# Publish to PyPI
twine upload dist/*
```

---

## License

[MIT](LICENSE)
