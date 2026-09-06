---
name: knowledge-retrieval
description: Retrieve architecture, decisions and validated project knowledge locally with QMD.
---

Repository Markdown is authoritative; QMD is rebuildable. Use just ai-search
with lexical mode for exact names, hybrid for conceptual questions, rerank only
when needed. Hybrid bypasses query expansion and reranking to limit local cost.
Refresh using just ai-knowledge-refresh after integration; --embed refreshes
local embeddings. Only the curated corpus and sanitized Beads view are indexed.
No raw conversations or production evidence. Returned citations include source
path, line, hash, modification time and current status. Stale source hashes are
rejected: refresh and re-read rather than citing a stale index.
Run the labeled recall benchmark before claiming the 90% top-five acceptance
criterion; fixture and actual evidence are distinct.
