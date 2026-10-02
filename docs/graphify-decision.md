# Decision: do not adopt Graphify

Evaluated Graphify 0.9.73 on Garbanzo AI 1.0.36 (source `0f673000cd1c`)
on 2026-10-01, using 75 code, documentation and architecture scenarios,
plus indexing and failure tests. Keep Serena, ast-grep, ripgrep and QMD.

Reasons:

- **Code reliability:** Graphify's internal graph captured only 7 of 16
  tested reference sites. Same-named Dart factories collided, generated
  helpers were missing, and exact-ID path queries sometimes returned the
  wrong starting symbol or missed paths present in the graph.
- **Documentation quality:** Semantic Graphify and QMD both found an
  expected source on 37 of 38 questions. Graphify retrieved fewer of the
  expected files overall (65% versus 80%) and supplied no line citations.
  Their retrieval ordering differs, so these are operational observations,
  not equivalent ranking scores.
- **Indexing overhead:** Cloud semantic indexing took about 12 minutes;
  the tested local model timed out after 40 minutes. Faster saved-graph
  queries did not establish an overall workflow improvement.
- **Integration burden:** Source edits stayed stale until reindexing;
  some MCP failures returned error text without setting the error flag.

These were small, selected tool-level tests, not an end-to-end coding or
billing study. Compact static maps were useful in some cases, but the
benefit did not justify another default tool. Reconsider only if coverage,
source grounding and exact path handling improve. Evaluation artifacts
were removed after retaining this decision.
