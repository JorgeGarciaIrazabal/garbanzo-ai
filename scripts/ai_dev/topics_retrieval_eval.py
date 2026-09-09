"""Evaluate bilingual semantic recall with the configured embedding provider."""

from __future__ import annotations

import argparse
import asyncio
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any


def _cosine(left: list[float], right: list[float]) -> float:
    if len(left) != len(right):
        raise RuntimeError("embedding dimensions do not match")
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        raise RuntimeError("embedding provider returned a zero vector")
    return sum(a * b for a, b in zip(left, right, strict=True)) / (left_norm * right_norm)


def _load_fixture(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    payload = json.loads(path.read_text())
    corpus = payload.get("corpus")
    cases = payload.get("cases")
    if not isinstance(corpus, list) or not corpus:
        raise RuntimeError("retrieval evaluation corpus is empty")
    if not isinstance(cases, list) or not cases:
        raise RuntimeError("retrieval evaluation cases are empty")
    corpus_ids = {item["id"] for item in corpus}
    if len(corpus_ids) != len(corpus):
        raise RuntimeError("retrieval evaluation corpus IDs must be unique")
    for case in cases:
        if case.get("language") not in {"en", "es"}:
            raise RuntimeError(f"unsupported language in case {case.get('id')}")
        relevant = set(case.get("relevant", []))
        if not relevant or not relevant <= corpus_ids:
            raise RuntimeError(f"invalid relevant IDs in case {case.get('id')}")
    return corpus, cases


async def evaluate(fixture: Path) -> dict[str, Any]:
    from app.services.embedding_provider import get_embedding_provider

    corpus, cases = _load_fixture(fixture)
    provider = get_embedding_provider()
    texts = [item["text"] for item in corpus] + [case["query"] for case in cases]
    vectors = await provider.embed(texts)
    if len(vectors) != len(texts):
        raise RuntimeError("embedding provider returned an incomplete batch")
    corpus_vectors = vectors[: len(corpus)]
    query_vectors = vectors[len(corpus) :]

    rows: list[dict[str, Any]] = []
    by_language: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for case, query_vector in zip(cases, query_vectors, strict=True):
        ranked = sorted(
            (
                (_cosine(query_vector, vector), item["id"])
                for item, vector in zip(corpus, corpus_vectors, strict=True)
            ),
            reverse=True,
        )
        relevant = set(case["relevant"])
        rank = next(
            (index for index, (_, item_id) in enumerate(ranked, start=1) if item_id in relevant),
            None,
        )
        if rank is None:
            raise RuntimeError(f"no relevant corpus item ranked for {case['id']}")
        row = {
            "id": case["id"],
            "language": case["language"],
            "kind": case["kind"],
            "rank": rank,
            "top": ranked[0][1],
            "score": round(ranked[0][0], 4),
        }
        rows.append(row)
        by_language[case["language"]].append(row)

    metrics: dict[str, dict[str, float | int]] = {}
    for language, language_rows in sorted(by_language.items()):
        metrics[language] = {
            "cases": len(language_rows),
            "recall_at_1": sum(row["rank"] == 1 for row in language_rows) / len(language_rows),
            "recall_at_3": sum(row["rank"] <= 3 for row in language_rows) / len(language_rows),
            "mrr": sum(1 / row["rank"] for row in language_rows) / len(language_rows),
        }
    failed = [
        language
        for language, values in metrics.items()
        if values["recall_at_1"] < 0.75 or values["recall_at_3"] < 1.0 or values["mrr"] < 0.8
    ]
    if failed:
        detail = ", ".join(f"{row['id']}=rank{row['rank']}:{row['top']}" for row in rows)
        raise RuntimeError(
            f"bilingual retrieval threshold failed for {', '.join(failed)} ({detail})"
        )
    return {
        "model": getattr(provider, "model", type(provider).__name__),
        "metrics": metrics,
        "cases": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fixture",
        type=Path,
        default=Path(__file__).parent / "fixtures" / "topics_retrieval_eval.json",
    )
    args = parser.parse_args()
    result = asyncio.run(evaluate(args.fixture.resolve()))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
