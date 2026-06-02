"""
OpenAI transcript formatter with a reliability-first fallback.

Design contract:
  format_transcript() ALWAYS returns a valid markdown string.
  If OpenAI is unavailable or fails, the raw transcript is wrapped in a
  minimal markdown note so no captured speech is ever discarded.
"""
from __future__ import annotations

import logging
import textwrap
from datetime import datetime

logger = logging.getLogger("whisper.formatter")

# ---------------------------------------------------------------------------
# Prompt — tuned for technical research notes
# ---------------------------------------------------------------------------
_SYSTEM_PROMPT = """\
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


def format_transcript(transcript: str, timestamp: str) -> str:
    """
    Format transcript via OpenAI.
    Falls back to _fallback_markdown() on any failure so content is never lost.
    """
    from whisper_note import config as cfg_mod
    cfg = cfg_mod.get()

    if not cfg.openai_api_key:
        logger.warning(
            "OPENAI_API_KEY not set — using fallback formatter. "
            "Export the variable to enable AI formatting."
        )
        return _fallback_markdown(transcript, timestamp, reason="OPENAI_API_KEY not set")

    try:
        from openai import OpenAI
        client = OpenAI(api_key=cfg.openai_api_key, timeout=cfg.openai_timeout)
        logger.info(f"Sending to OpenAI ({cfg.openai_model}) ...")

        completion = client.chat.completions.create(
            model=cfg.openai_model,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": f"Format this voice transcript as a markdown note:\n\n{transcript}",
                },
            ],
        )
        markdown = completion.choices[0].message.content
        logger.info(f"OpenAI returned {len(markdown)} chars.")
        return markdown

    except Exception as exc:
        logger.error(f"OpenAI formatting failed: {exc}")
        logger.warning("Falling back to raw-transcript markdown to preserve content.")
        return _fallback_markdown(transcript, timestamp, reason=str(exc))


# ---------------------------------------------------------------------------
# Fallback — always produces a valid note
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
