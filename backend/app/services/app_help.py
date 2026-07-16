"""Retrieval over the app user guide for the ``app_help`` native tool.

The corpus is the task-oriented markdown guides in ``app/docs/help`` — a
dozen short files of "How do I X?" sections. At that size plain keyword
scoring over heading-split sections answers real queries ("how do I pin a
conversation") essentially verbatim, so this deliberately skips embeddings:
no model dependency, no startup cost, nothing to go stale. If the corpus
ever outgrows keyword quality, swap ``search_help`` for the existing
``embedding_provider`` behind the same signature.

Docs are static for the life of the process, so they're parsed once on
first use and cached in module memory.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

HELP_DOCS_DIR = Path(__file__).resolve().parent.parent / "docs" / "help"

# Words too common in "how do I …" queries to carry any signal.
_STOPWORDS = frozenset({
    "a", "an", "and", "are", "can", "do", "does", "for", "how", "i", "in",
    "is", "it", "my", "of", "on", "or", "the", "to", "what", "when",
    "where", "which", "with", "you", "your",
})  # fmt: skip

_WORD_RE = re.compile(r"[a-z0-9@#/']+")


@dataclass(frozen=True)
class HelpSection:
    """One ``## How do I …`` section of a guide file."""

    area: str  # the file's # H1, e.g. "Chat"
    heading: str  # the section's ## H2
    body: str
    # Pre-tokenized for scoring.
    heading_tokens: frozenset[str]
    body_tokens: frozenset[str]
    area_tokens: frozenset[str]


def _tokenize(text: str) -> frozenset[str]:
    # Crude plural folding (rooms→room, actions→action) — enough stemming
    # for a corpus this small without dragging in a stemmer.
    return frozenset(
        (w[:-1] if w.endswith("s") and len(w) > 3 else w)
        for w in _WORD_RE.findall(text.lower())
        if w not in _STOPWORDS
    )


def _parse_file(path: Path) -> list[HelpSection]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    area = path.stem.replace("-", " ").title()
    sections: list[HelpSection] = []
    heading: str | None = None
    body: list[str] = []
    intro: list[str] = []

    def flush() -> None:
        if heading is not None:
            body_text = "\n".join(body).strip()
            sections.append(
                HelpSection(
                    area=area,
                    heading=heading,
                    body=body_text,
                    heading_tokens=_tokenize(heading),
                    body_tokens=_tokenize(body_text),
                    area_tokens=_tokenize(area),
                )
            )

    for line in lines:
        if line.startswith("# ") and not line.startswith("## "):
            area = line[2:].strip()
        elif line.startswith("## "):
            flush()
            heading = line[3:].strip()
            body = []
        elif heading is None:
            intro.append(line)
        else:
            body.append(line)
    flush()

    # A file's intro paragraph (text before the first ##) describes the
    # feature itself — index it as its own section so "what are rooms?"
    # style questions land somewhere.
    intro_text = "\n".join(intro).strip()
    if intro_text:
        sections.insert(
            0,
            HelpSection(
                area=area,
                heading=f"What is {area}?",
                body=intro_text,
                heading_tokens=_tokenize(area),
                body_tokens=_tokenize(intro_text),
                area_tokens=_tokenize(area),
            ),
        )
    return sections


_sections_cache: list[HelpSection] | None = None


def _sections() -> list[HelpSection]:
    global _sections_cache
    if _sections_cache is None:
        sections: list[HelpSection] = []
        for path in sorted(HELP_DOCS_DIR.glob("*.md")):
            try:
                sections.extend(_parse_file(path))
            except Exception:
                logger.exception("Failed to parse help doc %s", path)
        _sections_cache = sections
        logger.info("Loaded %d help sections from %s", len(sections), HELP_DOCS_DIR)
    return _sections_cache


def search_help(query: str, *, limit: int = 3) -> list[dict[str, str]]:
    """Top help sections for ``query`` as ``{area, heading, content}`` dicts.

    Heading matches dominate (the headings ARE the questions users ask),
    area-name matches break ties toward the right feature, body matches
    fill in the rest. Sections with zero overlap never surface.
    """
    tokens = _tokenize(query)
    if not tokens:
        return []

    scored: list[tuple[float, HelpSection]] = []
    for section in _sections():
        score = (
            3.0 * len(tokens & section.heading_tokens)
            + 2.0 * len(tokens & section.area_tokens)
            + 1.0 * len(tokens & section.body_tokens)
        )
        if score > 0:
            scored.append((score, section))

    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [
        {"area": s.area, "heading": s.heading, "content": s.body} for _score, s in scored[:limit]
    ]
