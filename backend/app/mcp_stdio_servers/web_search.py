# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "mcp>=1,<2",
#   "rich",
#   "ollama",
# ]
# ///
"""
MCP stdio server exposing Ollama web_search and web_fetch as tools.

Auth: the Ollama client reads ``OLLAMA_API_KEY`` from the environment and sends
it as a Bearer token. The key is resolved in this order, so no secret has to be
duplicated in the MCP client config:

1. An existing ``OLLAMA_API_KEY`` env var (how prod injects it — the backend
   container sets it, and this subprocess inherits it).
2. ``OLLAMA_API_KEY`` read from the backend ``.env`` file (the dev/IDE case,
   where the var is not exported into the process environment).
"""

from __future__ import annotations

import math
import os
import re
from collections import Counter
from pathlib import Path
from typing import Any


def _load_api_key_from_env_file() -> None:
    """Populate ``OLLAMA_API_KEY`` from backend/.env if it isn't already set.

    Looks for a ``.env`` next to the backend package root (this file lives at
    ``backend/app/mcp_stdio_servers/web_search.py``) and, as a fallback, in the
    current working directory. A real environment variable always wins, so prod
    (which injects the var) never touches the filesystem.
    """
    if os.environ.get("OLLAMA_API_KEY"):
        return

    candidates = [
        Path(__file__).resolve().parents[2] / ".env",  # backend/.env
        Path.cwd() / ".env",
        Path.cwd() / "backend" / ".env",
    ]
    for env_path in candidates:
        if not env_path.is_file():
            continue
        for raw in env_path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            if key.strip() == "OLLAMA_API_KEY":
                os.environ.setdefault("OLLAMA_API_KEY", value.strip().strip("'\""))
                return


_load_api_key_from_env_file()

from mcp.server.fastmcp import FastMCP  # noqa: E402
from ollama import Client  # noqa: E402  (imports after the key is in the environment)

client = Client()

SEARCH_EXCERPT_CHARS = 1200
FETCH_EXCERPT_CHARS = 6000
MAX_FETCH_CHARS = 12000
_PASSAGE_CHARS = 600
_STOP_WORDS = frozenset(
    [
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "by",
        "for",
        "from",
        "how",
        "i",
        "in",
        "is",
        "it",
        "of",
        "on",
        "or",
        "that",
        "the",
        "this",
        "to",
        "was",
        "what",
        "when",
        "where",
        "which",
        "who",
        "with",
        "de",
        "del",
        "el",
        "en",
        "es",
        "la",
        "las",
        "los",
        "para",
        "por",
        "que",
        "un",
        "una",
        "y",
    ]
)


def _terms(text: str) -> set[str]:
    return set(re.findall(r"\w+", text.casefold())) - _STOP_WORDS


def _passages(text: str) -> list[str]:
    """Split even a single long paragraph so relevant endings remain retrievable."""
    passages = []
    start = 0
    while start < len(text):
        end = min(start + _PASSAGE_CHARS, len(text))
        if end < len(text):
            boundary = text.rfind(" ", start + _PASSAGE_CHARS // 2, end)
            if boundary != -1:
                end = boundary
        passage = text[start:end].strip()
        if passage:
            passages.append(passage)
        start = end
    return passages


def _excerpt(content: str, query: str, max_chars: int) -> tuple[str, bool]:
    """Extract source passages without spending another LLM call or inventing text.

    Rare query terms receive more weight than repeated navigation terms. Selected
    passages retain document order; omissions are marked. No matches is explicit.
    """
    if len(content) <= max_chars:
        return content, bool(_terms(query) & _terms(content))
    passages = _passages(content)
    terms = _terms(query)
    hits = [_terms(passage) & terms for passage in passages]
    counts = Counter(term for hit in hits for term in hit)
    scores = [sum(math.log1p(len(passages) / counts[term]) for term in hit) for hit in hits]
    ranked = sorted(range(len(passages)), key=lambda i: (-scores[i], i))
    if not any(scores):
        return content[:max_chars], False
    selected: dict[int, str] = {}
    remaining = max_chars
    seen = set()
    for index in ranked:
        if scores[index] == 0 or remaining <= 5:
            break
        passage = passages[index]
        if passage in seen:
            continue
        seen.add(passage)
        # Reserve the separator so the returned content always fits its budget.
        allowance = remaining - (5 if selected else 0)
        selected[index] = passage[:allowance]
        remaining -= len(selected[index]) + (5 if len(selected) > 1 else 0)
    return "\n...\n".join(selected[i] for i in sorted(selected)), True


def _web_search_impl(query: str, max_results: int = 3) -> dict[str, Any]:
    if not query.strip():
        raise ValueError("query must not be empty")
    if not 1 <= max_results <= 5:
        raise ValueError("max_results must be between 1 and 5")
    res = client.web_search(query=query, max_results=max_results)
    results = []
    seen_urls: set[str] = set()
    for result in res.results[:max_results]:
        if result.url and result.url in seen_urls:
            continue
        if result.url:
            seen_urls.add(result.url)
        content = result.content or ""
        excerpt, matched = _excerpt(content, query, SEARCH_EXCERPT_CHARS)
        results.append(
            {
                "title": (result.title or "")[:300],
                "url": result.url,
                "content": excerpt,
                "total_chars": len(content),
                "truncated": len(content) > len(excerpt),
                "query_matched": matched,
            }
        )
    return {
        "results": results,
        "content_limit_per_result": SEARCH_EXCERPT_CHARS,
        "usage": "Use these excerpts first; web_fetch(url, query=...) retrieves focused details.",
    }


def _web_fetch_impl(
    url: str, query: str = "", max_chars: int = FETCH_EXCERPT_CHARS, offset: int = 0
) -> dict[str, Any]:
    if not 500 <= max_chars <= MAX_FETCH_CHARS:
        raise ValueError(f"max_chars must be between 500 and {MAX_FETCH_CHARS}")
    if offset < 0:
        raise ValueError("offset must not be negative")
    if query.strip() and offset:
        raise ValueError(
            "offset is only supported without a query; use another query for more excerpts"
        )
    res = client.web_fetch(url=url)
    content = res.content or ""
    if query.strip():
        excerpt, matched = _excerpt(content, query, max_chars)
        return {
            "url": url,
            "title": (res.title or "")[:300],
            "content": excerpt,
            "total_chars": len(content),
            "truncated": len(content) > len(excerpt),
            "selection": "query_excerpts",
            "query_matched": matched,
            "usage": "Change query for other details, or omit query and use offset to read pages.",
        }
    if offset > len(content):
        raise ValueError(f"offset exceeds page length ({len(content)} characters)")
    end = min(offset + max_chars, len(content))
    links = list(dict.fromkeys(res.links or []))
    return {
        "url": url,
        "title": (res.title or "")[:300],
        "content": content[offset:end],
        "total_chars": len(content),
        "truncated": offset > 0 or end < len(content),
        "selection": "page",
        "offset": offset,
        "next_offset": end if end < len(content) else None,
        "links": links[:10],
        "links_omitted": max(0, len(links) - 10),
    }


app = FastMCP("ollama-search-fetch")


@app.tool()
def web_search(query: str, max_results: int = 3) -> dict[str, Any]:
    """
    Search the web for concise source excerpts and citation URLs.
    Use these results directly when they answer the question. Fetch only sources
    needing more detail, passing a focused query to web_fetch to save context.

    Args:
      query: The search query to run.
      max_results: Maximum results to return, 1–5 (default: 3).

    Returns:
      Source titles, URLs and at most 1200 content characters per result.
      Truncation is explicit; excerpts are source text, not generated summaries.
    """

    return _web_search_impl(query=query, max_results=max_results)


@app.tool()
def web_fetch(
    url: str, query: str = "", max_chars: int = FETCH_EXCERPT_CHARS, offset: int = 0
) -> dict[str, Any]:
    """
    Fetch focused source passages from a web page. Prefer a query describing
    the facts needed; avoid loading full pages into chat unnecessarily.

    Args:
      url: The absolute URL to fetch.
      query: Words describing the needed facts. Empty returns a sequential page.
      max_chars: Content budget, 500–12000 characters (default: 6000).
      offset: Character offset for sequential paging without a query (default: 0).

    Returns:
      Source URL, title, bounded content and explicit truncation. Query mode
      reports query_matched=false if only an opening excerpt was available.
      Sequential mode returns next_offset; pass it to read further if needed.
    """

    return _web_fetch_impl(url=url, query=query, max_chars=max_chars, offset=offset)


if __name__ == "__main__":
    app.run()
