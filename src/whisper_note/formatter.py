"""
Transcript formatter — single OpenAI-compatible code path.

Works with any provider that speaks the OpenAI chat completions API:
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

logger = logging.getLogger("whisper.formatter")

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
# Public entry point
# ---------------------------------------------------------------------------

def format_transcript(transcript: str, timestamp: str) -> str:
    """Always returns valid markdown. Never raises."""
    from whisper_note import config as cfg_mod
    cfg = cfg_mod.get()

    result = _try_llm(transcript, cfg)
    if result:
        return result

    logger.warning("LLM unavailable — saving raw transcript.")
    return _fallback_markdown(transcript, timestamp, reason="LLM unavailable")


# ---------------------------------------------------------------------------
# Generic LLM call (OpenAI-compatible)
# ---------------------------------------------------------------------------

def _try_llm(transcript: str, cfg) -> str | None:
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
        text = completion.choices[0].message.content or ""
        return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()

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
