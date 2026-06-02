"""
Transcript formatter — two backends, selected by cfg.llm_backend.

  "local" (default) — in-process llama.cpp loading a local GGUF model.
                      Fully on-device, no server.  Model loaded once at startup.
  "http"            — any OpenAI-compatible chat completions endpoint:
                        Ollama  → WN_LLM_URL=http://127.0.0.1:11434/v1  WN_LLM_KEY=ollama
                        OpenAI  → WN_LLM_URL=https://api.openai.com/v1   WN_LLM_KEY=sk-...
                        Claude  → WN_LLM_URL=https://api.anthropic.com/v1 WN_LLM_KEY=sk-ant-...

Falls back to a raw-transcript note if the LLM is unavailable.
"""
from __future__ import annotations

import logging
import re
import textwrap
from datetime import datetime
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from llama_cpp import Llama

logger = logging.getLogger("whisper.formatter")

# Local llama.cpp model — loaded once via load_model() to avoid per-note overhead.
_local_llm: Optional["Llama"] = None

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
_SYSTEM_PROMPT = """\
/no_think
You are a precise technical note formatter that converts voice transcripts \
into well-structured Obsidian markdown notes.

## Preservation rules — apply without exception

Preserve the following character-for-character. Never normalise, rewrite, \
or "improve" them:

- Shell commands and one-liners          → fenced code block  ```bash
- URLs                                   → exactly as spoken
- IP addresses, hostnames, ports         → exactly as spoken
- CVE identifiers (CVE-YYYY-NNNNN)       → exactly as spoken
- HTTP requests / responses              → fenced code block  ```http
- JSON / YAML / XML                      → fenced code block with language tag
- Source code, scripts, payloads         → fenced code block with language tag
- Tool names + version numbers           → exactly as spoken (nmap 7.94, etc.)
- Package / library names                → exactly as spoken
- Security terms (RCE, LFI, SSRF, etc.) → exactly as spoken
- Hex values, hashes, base64 strings     → exactly as spoken
- Error messages and stack traces        → fenced code block
- Regex patterns                         → inline code or code block

## Structure rules

- Open with a concise `## Title` heading drawn from the main topic
- Use `### Sub-headings` for distinct topics or procedural steps
- Bullet points (`-`) for unordered items; numbered lists only for sequences
- `inline code` for filenames, flags, options, and technical terms
- Short, direct sentences — no padding
- Do not add information not present in the transcript

## Output

Return only the markdown content. No preamble, no trailing explanation.
"""

_USER_PROMPT = "Format this voice transcript as a markdown note:\n\n{transcript}"


# ---------------------------------------------------------------------------
# Local backend model loading (llama.cpp + GGUF)
# ---------------------------------------------------------------------------

def load_model() -> None:
    """
    Load the local GGUF model into memory.  Optional but recommended: call once
    at startup (see main.py) so the first note isn't slowed by model loading.
    No-op unless the local backend is selected.  Never raises — a failure here
    leaves the model unloaded and format_transcript() falls back to raw notes.
    """
    global _local_llm
    from whisper_note import config as cfg_mod
    cfg = cfg_mod.get()

    if cfg.llm_backend != "local" or _local_llm is not None:
        return

    try:
        from llama_cpp import Llama
        logger.info(f"Loading local LLM (GGUF): {cfg.llm_gguf_path}")
        _local_llm = Llama(
            model_path=str(cfg.llm_gguf_path),
            n_ctx=cfg.llm_n_ctx,
            n_threads=cfg.llm_n_threads,
            verbose=False,
        )
        logger.info("Local LLM ready.")
    except Exception as exc:
        logger.error(f"Failed to load local LLM ({cfg.llm_gguf_path}): {exc}")
        _local_llm = None


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def format_transcript(transcript: str, timestamp: str) -> str:
    """Always returns valid markdown. Never raises."""
    from whisper_note import config as cfg_mod
    cfg = cfg_mod.get()

    if cfg.llm_backend == "local":
        result = _try_local_llm(transcript, cfg)
    else:
        result = _try_http_llm(transcript, cfg)

    if result:
        return result

    logger.warning("LLM unavailable — saving raw transcript.")
    return _fallback_markdown(transcript, timestamp, reason="LLM unavailable")


def _clean(text: str) -> str:
    """
    Normalise raw model output into a clean markdown note:
      - drop any <think>…</think> reasoning blocks
      - unwrap a whole-document ```markdown … ``` fence that smaller models
        sometimes add despite being told to return only markdown content
    """
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()

    # Unwrap an outer ```markdown / ```md fence wrapping the entire response.
    m = re.match(r"^```(?:markdown|md)\s*\n(.*)", text, flags=re.DOTALL | re.IGNORECASE)
    if m:
        text = m.group(1)
        text = re.sub(r"\n?```\s*$", "", text)  # drop the matching closing fence, if present

    return text.strip()


# ---------------------------------------------------------------------------
# Local backend — in-process llama.cpp (GGUF), ChatML prompt
# ---------------------------------------------------------------------------

def _try_local_llm(transcript: str, cfg) -> str | None:
    global _local_llm
    if _local_llm is None:
        load_model()  # lazy load if startup didn't
    if _local_llm is None:
        return None

    logger.info(f"Formatting via local GGUF: {cfg.llm_gguf_path.name}")
    prompt = (
        "<|im_start|>system\n"
        f"{_SYSTEM_PROMPT}<|im_end|>\n"
        "<|im_start|>user\n"
        f"{_USER_PROMPT.format(transcript=transcript)}<|im_end|>\n"
        "<|im_start|>assistant\n"
    )

    try:
        response = _local_llm(
            prompt,
            max_tokens=cfg.llm_max_tokens,
            temperature=cfg.llm_temperature,
            top_p=0.9,
            repeat_penalty=1.1,
            stop=["<|im_end|>", "<|im_start|>"],
        )
    except Exception as exc:
        logger.error(f"Local LLM formatting failed: {exc}")
        return None

    text = _clean(response["choices"][0]["text"] or "")
    if not text:
        logger.warning("Local LLM returned empty content.")
        return None
    logger.info(f"Local LLM returned {len(text)} chars.")
    return text


# ---------------------------------------------------------------------------
# HTTP backend — OpenAI-compatible endpoint
# ---------------------------------------------------------------------------

def _try_http_llm(transcript: str, cfg) -> str | None:
    import time
    import httpx
    from openai import OpenAI, RateLimitError

    logger.info(f"Formatting via {cfg.llm_url}  model={cfg.llm_model}")
    client = OpenAI(
        base_url=cfg.llm_url,
        api_key=cfg.llm_key,
        max_retries=0,
        default_headers={"anthropic-version": "2023-06-01"},
        http_client=httpx.Client(
            timeout=httpx.Timeout(
                connect=10.0,
                read=float(cfg.llm_timeout),
                write=10.0,
                pool=10.0,
            )
        ),
    )

    def _call() -> str:
        completion = client.chat.completions.create(
            model=cfg.llm_model,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user",   "content": _USER_PROMPT.format(transcript=transcript)},
            ],
        )
        return _clean(completion.choices[0].message.content or "")

    try:
        text = _call()
    except RateLimitError:
        logger.warning("Rate limit hit — retrying in 10 s …")
        time.sleep(10)
        try:
            text = _call()
        except Exception as exc:
            logger.error(f"LLM formatting failed after retry: {exc}")
            return None
    except Exception as exc:
        logger.error(f"LLM formatting failed: {exc}")
        return None

    if not text:
        logger.warning("LLM returned empty content.")
        return None
    logger.info(f"LLM returned {len(text)} chars.")
    return text


# ---------------------------------------------------------------------------
# Raw fallback — always produces a valid note
# ---------------------------------------------------------------------------

def _fallback_markdown(transcript: str, timestamp: str, reason: str = "") -> str:
    try:
        dt = datetime.strptime(timestamp, "%Y%m%d_%H%M%S")
        date_str = dt.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        date_str = timestamp

    warning = ""
    if reason:
        warning = textwrap.dedent(f"""\
            > [!warning] AI formatting unavailable
            > {reason}
            > Raw transcript preserved below.

        """)

    return textwrap.dedent(f"""\
        ## Voice Note — {date_str}

        {warning}### Transcript

        {transcript}
    """)
