"""Verify representative Python and generated-model Dart references via Serena MCP."""

import asyncio
import json
import os
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]


async def main():
    root = ROOT
    parameters = StdioServerParameters(
        command="just", args=["ai-serena"], cwd=root, env=os.environ.copy()
    )
    results = {}
    async with asyncio.timeout(240):
        async with stdio_client(parameters) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                listed = await session.list_tools()
                names = {tool.name for tool in listed.tools}
                for path, symbol in [
                    ("backend/app/models/report.py", "Report"),
                    ("lib/features/chat/models/conversation.dart", "Conversation"),
                ]:
                    response = await session.call_tool(
                        "find_symbol",
                        {"name_path_pattern": symbol, "relative_path": path, "include_body": False},
                    )
                    if response.isError:
                        raise RuntimeError(f"Serena could not resolve {path}:{symbol}")
                    text = "\n".join(
                        item.text for item in response.content if hasattr(item, "text")
                    )
                    if symbol not in text:
                        raise RuntimeError(f"Serena returned no symbol for {path}:{symbol}")
                    refs = await session.call_tool(
                        "find_referencing_symbols", {"name_path": symbol, "relative_path": path}
                    )
                    references = "\n".join(
                        item.text for item in refs.content if hasattr(item, "text")
                    )
                    if refs.isError or references.strip() in {"[]", "{}", ""}:
                        raise RuntimeError(f"Serena returned no references for {symbol}")
                    results[path] = {"symbol": symbol, "resolved": True, "references_found": True}
                generated = await session.call_tool(
                    "get_symbols_overview",
                    {
                        "relative_path": "lib/features/chat/models/conversation.freezed.dart",
                        "depth": 0,
                    },
                )
                generated_text = "\n".join(
                    item.text for item in generated.content if hasattr(item, "text")
                )
                if generated.isError or "Conversation" not in generated_text:
                    raise RuntimeError(
                        "Serena could not resolve generated Conversation declarations"
                    )
                results["generated_declarations"] = True
                results["tools"] = len(names)
    output = root / ".ai/local/navigation-smoke.json"
    output.write_text(json.dumps(results, indent=2) + "\n")
    output.chmod(0o600)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
