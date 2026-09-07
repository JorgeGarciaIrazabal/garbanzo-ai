"""Rebuildable local QMD corpus with source hashes and current citations."""

import hashlib
import json
import re
import time
from datetime import UTC, datetime
from pathlib import Path

from .common import WorkflowError, local_dir, lock, read_json, run, write_json

# Deliberate public-document allowlist: never ingest logs, evidence or conversations.
DOCUMENTS = [
    "AGENTS.md",
    "backend/AGENTS.md",
    "lib/AGENTS.md",
    "deploy/AGENTS.md",
    "docs/architecture.md",
    "docs/api.md",
    "docs/database.md",
    "docs/environment.md",
    "docs/coverage-strategy.md",
    "docs/ai-development.md",
    "docs/ai-workflow-guide.md",
    "deploy/README.md",
    "setup.md",
    "TASKS.md",
]


def source_paths(root: Path):
    paths = [root / name for name in DOCUMENTS]
    paths.extend((root / "backend/app/docs/help").glob("*.md"))
    paths.extend((root / ".agents/skills").glob("*/SKILL.md"))
    return sorted({p for p in paths if p.is_file() and p.resolve().is_relative_to(root.resolve())})


def refresh(root: Path, embed: bool = False) -> dict:
    with lock(root, "knowledge"):
        qmd = root / ".qmd"
        qmd.mkdir(exist_ok=True)
        corpus = root / ".ai/local/knowledge"
        corpus.mkdir(exist_ok=True)
        old = read_json(local_dir(root) / "knowledge-manifest.json", {"sources": {}})
        sources = {}
        for path in source_paths(root):
            relative = path.relative_to(root).as_posix()
            content = path.read_text()
            digest = hashlib.sha256(content.encode()).hexdigest()
            destination = corpus / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(content)
            sources[relative] = {
                "sha256": digest,
                "modified_at": datetime.fromtimestamp(path.stat().st_mtime, UTC).isoformat(),
                "lines": len(content.splitlines()),
                "status": "current",
            }
        for relative in old["sources"]:
            if relative not in sources:
                candidate = corpus / relative
                if not candidate.resolve().is_relative_to(corpus.resolve()):
                    raise WorkflowError("knowledge manifest contains an unsafe source path")
                candidate.unlink(missing_ok=True)
        # Relative collection paths are resolved from project root by qmd.
        (qmd / "index.yml").write_text(
            'collections:\n  garbanzo:\n    path: .ai/local/knowledge\n    pattern: "**/*.md"\n'
        )
        run(root, ["qmd", "update"], timeout=180)
        if embed:
            run(
                root,
                [
                    "qmd",
                    "embed",
                    "--timeout",
                    "10",
                    "--max-docs-per-batch",
                    "8",
                    "--max-batch-mb",
                    "2",
                ],
                timeout=660,
            )
        manifest = {
            "indexed_at": datetime.now(UTC).isoformat(),
            "sources": sources,
            "superseded": {
                name: data
                for name, data in old["sources"].items()
                if name not in sources or data["sha256"] != sources[name]["sha256"]
            },
        }
        write_json(local_dir(root) / "knowledge-manifest.json", manifest)
        return {"status": "indexed", "documents": len(sources), "embeddings_refreshed": embed}


def search(root: Path, query: str, mode: str = "lexical", limit: int = 5) -> dict:
    manifest = read_json(local_dir(root) / "knowledge-manifest.json")
    if not manifest:
        raise WorkflowError("Knowledge index missing; run just ai-knowledge-refresh")
    if not query.strip() or "\n" in query:
        raise WorkflowError("Use a nonempty, single-line query")
    argv = ["qmd", "search" if mode == "lexical" else "query"]
    # Typed queries avoid unnecessary query-expansion model downloads.
    argv.append(query if mode == "lexical" else f"lex: {query}\nvec: {query}")
    argv.extend(["--format", "json", "--full-path", "--line-numbers", "-n", str(limit)])
    if mode == "hybrid":
        argv.append("--no-rerank")
    start = time.monotonic()
    records = json.loads(run(root, argv, timeout=180))
    output = []
    stale = []
    for row in records:
        file = row.get("file", row.get("path", ""))
        prefix = ".ai/local/knowledge/"
        if prefix in file:
            relative = file.split(prefix, 1)[1]
        elif file.startswith("qmd://garbanzo/"):
            relative = file.removeprefix("qmd://garbanzo/")
        else:
            continue
        source = root / relative
        evidence = manifest["sources"].get(relative)
        if (
            not evidence
            or not source.is_file()
            or hashlib.sha256(source.read_bytes()).hexdigest() != evidence["sha256"]
        ):
            stale.append(relative)
            continue
        snippet = row.get("snippet", "")
        match = re.search(r"@@ -(\d+)", snippet)
        line = int(match[1]) if match else 1
        output.append(
            {
                "path": relative,
                "line": line,
                "sha256": evidence["sha256"],
                "modified_at": evidence["modified_at"],
                "status": "current",
                "score": row.get("score"),
                "snippet": snippet,
                "citation": f"{source}:{line}",
            }
        )
    result = {
        "results": output,
        "stale_sources": stale,
        "elapsed_seconds": time.monotonic() - start,
        "mode": mode,
    }
    write_json(
        local_dir(root) / "retrieval-last.json",
        {key: value for key, value in result.items() if key != "results"},
    )
    return result


def benchmark(root: Path, fixture: Path, mode: str) -> dict:
    questions = json.loads(fixture.read_text())["questions"]
    if len(questions) < 30:
        raise WorkflowError("Acceptance requires at least 30 labeled questions")
    hits = 0
    rows = []
    for question in questions:
        response = search(root, question["query"], mode)
        found = {row["path"] for row in response["results"]}
        hit = bool(found.intersection(question["expected_files"]))
        hits += hit
        rows.append(
            {
                "query": question["query"],
                "hit": hit,
                "paths": sorted(found),
                "elapsed_seconds": response["elapsed_seconds"],
            }
        )
    result = {
        "questions": len(questions),
        "recall_at_5": hits / len(questions),
        "passed": hits / len(questions) >= 0.9,
        "mode": mode,
        "results": rows,
    }
    write_json(local_dir(root) / "retrieval-benchmark.json", result)
    return result


def register(subparsers):
    refresh_parser = subparsers.add_parser("knowledge-refresh")
    refresh_parser.add_argument("--embed", action="store_true")
    refresh_parser.set_defaults(func=lambda args: refresh(args.root, args.embed))
    parser = subparsers.add_parser("search")
    parser.add_argument("query", nargs="?", default="")
    parser.add_argument("--mode", choices=["lexical", "hybrid", "rerank"], default="lexical")
    parser.add_argument("--benchmark", type=Path)
    parser.set_defaults(
        func=lambda args: (
            benchmark(args.root, args.benchmark, args.mode)
            if args.benchmark
            else search(args.root, args.query, args.mode)
        )
    )
