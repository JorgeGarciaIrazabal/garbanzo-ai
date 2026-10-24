"""Regression tests for the standalone Ollama web-search MCP server."""

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.mcp_stdio_servers import web_search as web
from app.mcp_stdio_servers.web_search import app
from app.services.agent_turn import stringify_tool_result, truncate_tool_result

BACKEND_ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.asyncio
async def test_registers_search_and_fetch_tools():
    tools = await app.list_tools()

    assert {tool.name for tool in tools} == {"web_fetch", "web_search"}
    fetch = next(tool for tool in tools if tool.name == "web_fetch")
    assert {"query", "offset", "max_chars"} <= fetch.inputSchema["properties"].keys()


def test_inline_environment_stays_on_compatible_mcp_major():
    script = (BACKEND_ROOT / "app/mcp_stdio_servers/web_search.py").read_text()
    pyproject = (BACKEND_ROOT / "pyproject.toml").read_text()

    assert '"mcp>=1,<2"' in script
    assert '"mcp>=1.0,<2"' in pyproject


def test_search_keeps_relevant_tail_and_citations_with_bounded_content(monkeypatch):
    content = "Navigation and unrelated page content. " * 2000
    content += "\nThe Aurora telescope launch date is October 24, 2026.\n"
    result = SimpleNamespace(
        title="Launch schedule", url="https://example.com/launch", content=content
    )
    monkeypatch.setattr(
        web.client, "web_search", lambda **kwargs: SimpleNamespace(results=[result, result])
    )

    response = web.web_search("Aurora telescope launch date")

    assert len(response["results"]) == 1
    excerpt = response["results"][0]
    assert "October 24, 2026" in excerpt["content"]
    assert excerpt["url"] == result.url
    assert excerpt["title"] == result.title
    assert len(excerpt["content"]) <= 1200
    assert excerpt["truncated"] is True
    assert excerpt["query_matched"] is True
    assert excerpt["total_chars"] == len(content)


def test_focused_fetch_finds_middle_of_long_single_paragraph_without_extra_llm(monkeypatch):
    content = "Unrelated navigation. " * 1000
    content += "Warranty coverage includes repairs for seven years. "
    content += "Unrelated footer. " * 1000
    monkeypatch.setattr(
        web.client,
        "web_fetch",
        lambda **kwargs: SimpleNamespace(title="Terms", content=content, links=[]),
    )

    response = web.web_fetch("https://example.com/terms", query="warranty coverage", max_chars=800)

    assert "seven years" in response["content"]
    assert len(response["content"]) <= 800
    assert response["url"] == "https://example.com/terms"
    assert response["selection"] == "query_excerpts"
    assert response["query_matched"] is True
    assert response["truncated"] is True


def test_fetch_paging_recovers_full_source_and_bounds_links(monkeypatch):
    content = "Beginning. " * 1400 + "Final condition."
    links = [f"https://example.com/{i}" for i in range(100)]
    monkeypatch.setattr(
        web.client,
        "web_fetch",
        lambda **kwargs: SimpleNamespace(title="Terms", content=content, links=links),
    )
    parts = []
    offset = 0
    while offset is not None:
        response = web.web_fetch("https://example.com/terms", offset=offset)
        assert len(response["content"]) <= 6000
        assert len(response["links"]) == 10
        assert response["links_omitted"] == 90
        parts.append(response["content"])
        offset = response["next_offset"]
    assert "".join(parts) == content


@pytest.mark.asyncio
async def test_unicode_page_keeps_cursor_within_chat_result_budget(monkeypatch):
    """Escaping CJK text used to expand a bounded page past the generic cap."""
    monkeypatch.setattr(
        web.client,
        "web_fetch",
        lambda **kwargs: SimpleNamespace(title="资料", content="中文资料" * 4000, links=[]),
    )
    blocks, _structured = await app.call_tool(
        "web_fetch", {"url": "https://example.com", "max_chars": 12000}
    )
    mcp_content = blocks[0].text
    text = stringify_tool_result({"ok": True, "content": mcp_content})
    # This is the same stringification and cap used for persistence and model input.
    bounded = truncate_tool_result(text, 32000)
    restored = json.loads(json.loads(bounded)["content"])
    assert restored["next_offset"] == 12000
    assert restored["content"] == "中文资料" * 3000
    assert len(bounded) < 13000


def test_query_without_matches_is_explicit(monkeypatch):
    content = "Navigation only. " * 1000
    monkeypatch.setattr(
        web.client,
        "web_fetch",
        lambda **kwargs: SimpleNamespace(title="Home", content=content, links=[]),
    )
    response = web.web_fetch("https://example.com", query="missing fact", max_chars=500)
    assert response["query_matched"] is False
    assert response["truncated"] is True
    assert response["content"] == content[:500]


@pytest.mark.parametrize("max_chars", [0, 499, 12001])
def test_fetch_rejects_invalid_budget_before_calling_provider(max_chars, monkeypatch):
    def unexpected(**kwargs):
        pytest.fail("Invalid request must not call the provider")

    monkeypatch.setattr(web.client, "web_fetch", unexpected)
    with pytest.raises(ValueError, match="max_chars"):
        web.web_fetch("https://example.com", max_chars=max_chars)


@pytest.mark.parametrize("max_results", [0, 6])
def test_search_rejects_unbounded_result_counts(max_results):
    with pytest.raises(ValueError, match="max_results"):
        web.web_search("query", max_results=max_results)


def test_provider_failure_is_not_hidden(monkeypatch):
    def failed(**kwargs):
        raise RuntimeError("Search service unavailable")

    monkeypatch.setattr(web.client, "web_search", failed)
    monkeypatch.setattr(web.client, "web_fetch", failed)
    with pytest.raises(RuntimeError, match="unavailable"):
        web.web_search("query")
    with pytest.raises(RuntimeError, match="unavailable"):
        web.web_fetch("https://example.com")
