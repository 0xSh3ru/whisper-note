# Changelog

All notable changes to **whisper-note** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-06-03

### Added
- **Local LLM formatter backend** (`WN_LLM_BACKEND=local`, now the default): an
  in-process [llama.cpp](https://github.com/abetlen/llama-cpp-python) backend that
  loads a local GGUF model — fully on-device, no server required. The model is
  loaded once at startup.
- New config keys: `WN_LLM_BACKEND`, `WN_LLM_GGUF`, `WN_LLM_N_CTX`,
  `WN_LLM_THREADS`, `WN_LLM_MAX_TOKENS`, `WN_LLM_TEMPERATURE`.
- CLI flags `--llm-backend` and `--llm-gguf`.
- Packaging extras: install the backend you use with
  `pip install "whisper-note[local]"` or `pip install "whisper-note[http]"`.

### Changed
- The OpenAI-compatible backend (Ollama / OpenAI / Claude) is now selected with
  `WN_LLM_BACKEND=http` and ships in the optional `[http]` extra.
- `llama-cpp-python`, `openai`, and `httpx` are no longer core dependencies; they
  live in the `[local]` / `[http]` extras so installs only pull the chosen backend.
- Default Whisper model is now the local `~/models/faster-whisper-small` directory.
- Model output wrapped in a whole-document ` ```markdown ` fence is now unwrapped
  automatically (inner code blocks are preserved).
- Preflight checks are backend-aware; a missing backend package is non-fatal — the
  app still transcribes and saves raw notes.

### Fixed
- **Installer wizard**: corrected a broken whiptail capture idiom
  (`3>&1 1>&2 2>&3 >file` → `2>file`) that left every selected value empty and
  aborted the install with an `unbound variable` error. The installer now also
  installs the `[http]` extra and pins `WN_LLM_BACKEND=http` in the generated env.

## [1.0.4] and earlier

Initial public releases — voice capture, faster-whisper transcription,
OpenAI-compatible markdown formatting, GTK status widget, and the systemd
user-service installer. See the git history for details.

[1.1.0]: https://github.com/0xSh3ru/whisper-note/releases/tag/v1.1.0
