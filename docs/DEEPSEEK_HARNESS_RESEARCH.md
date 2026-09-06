# Research: DeepSeek Harness (`dsh`) vs OpenCode — can it replace the opencode agent?

**Date:** 2026-08-30
**Status:** research only — no code changes made
**Prompt origin:** <https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart> (note: an earlier round of this research mistakenly covered *Hermes Agent* by Nous Research — the link the user actually meant was DeepSeek Harness. That comparison is preserved in §8 for the record.)

## TL;DR

- **DeepSeek Harness (`dsh`)** is DeepSeek AI's open-source (MIT) agent harness, published ~2 weeks ago (repo created 2026-08-13) and already at ~204k stars. It is in an explicit **developer preview: "THERE WILL BE COMPATIBILITY-BREAKING CHANGES."** Everything is a plugin (Cordis composition); the `dsh` binary boots *profiles* (web, headless, sdk, sdk-minimal, acp) from a `$DSH_HOME` directory.
- **The integration model is a fundamentally different shape from opencode's.** Garbanzo today spawns `opencode serve` per workspace and talks HTTP+SSE. dsh's supported embedding path is **in-process Python SDK driving a bundled `dsh --profile sdk` subprocess over stdio JSON-RPC** (`pip install deepseek-harness-sdk`, `DeepSeekHarness(...)`, `harness.run(...)`). This is arguably an **architecturally better fit** for our FastAPI backend — no ports, no HTTP, no readiness polling, no pkill belt — but it is a full rewrite of the client layer, not a drop-in swap.
- **Feature coverage is good where it matters:** custom OpenAI-compatible providers (Ollama works via `base_url` + `DEEPSEEK_BASE_URL`), per-instance isolated state (`dsh_home`), per-run MCP servers via a `dsh-mcp-client` plugin config patch, permission/sandbox modes, session ids with resume, subagent events, durable JSONL sessions. **Abort is the one hard functional gap:** the SDK protocol has **no cancel method** — abandoning a turn means killing the runtime process.
- **Verdict:** feasible, and more promising than the Nous Hermes alternative (see §8), but not now. The blocking issues are **maturity** (2-week-old developer preview with a breaking-change guarantee; the community handbook's 170+ troubleshooting runbooks describe an operational surface still in flux) and the **abort gap**. The Python SDK's isolated-home + bundled-runtime design maps almost 1:1 onto our per-workspace/per-run model, so a future migration path exists and is clean.
- **Recommendation:** stay on opencode today; pin this doc as the reference. Revisit when dsh exits developer preview (or at least stabilizes its SDK protocol) *and* grows a mid-turn cancel. The provider-neutral naming refactor suggested at the end would keep the door open cheaply.

---

## 1. What DeepSeek Harness is

- **`dsh`** — open-source agent harness by DeepSeek AI (MIT), built on an "everything-is-a-plugin" architecture powered by [Cordis](https://github.com/cordiverse/cordis) (spatiotemporal composability; arXiv 2608.25512). Repo: <https://github.com/deepseek-ai/deepseek-harness>. Homepage: deepseek.com/harness. Feedback flows through GitHub Discussions.
- **Status:** developer preview, iterating rapidly through rc/alpha releases (rc.2 → rc.8, alpha.1 observed); explicit compatibility-breaking warning on the official README. Community handbook counts "271 hub repositories, 1,000 public `dsh-plugin` topic repositories" and ~1,000 unofficial same-name wrapper impostors — ecosystem is exploding but young.
- **Node requirement** for `npx @deepseek-ai/dsh web`: just Node.js (fork's source builds need `^22.19`/`>=24` + pnpm). **But the Python SDK ships a bundled runtime wheel** (`deepseek-harness-runtime-bin`) — "Running the SDK does not require system Node.js."
- **CLI entry modes** (apps/cli README): `dsh web` (Web UI on 127.0.0.1:3080), `dsh --profile headless "job"` (one fresh persisted session, print final answer, exit — the `opencode run` analog), `dsh --profile sdk` (JSON-RPC over stdio), `dsh --profile acp` (ACP for editors), `dsh plugin …` (pnpm-based plugin management per profile). Profiles live under `$DSH_HOME/profiles/<name>` and compose plugin bundle patches in layers; `--patch` overlays can be passed per invocation; `--dump-config`/`--dump-default-config` inspect composition without booting.
- **AGENTS.md support:** repo has its own AGENTS.md ("For agents, follow AGENTS.md") and a documented "AGENTS.md scope, visibility, and enforcement map" — the concept we use for repo instructions carries over.

## 2. The three integration surfaces (vs opencode's two)

| Garbanzo today (opencode) | DeepSeek Harness equivalent | Fit |
|---|---|---|
| `opencode serve --hostname --port` + HTTP + SSE (`POST /session`, `prompt_async`, `GET /event`, `GET /config`, abort) | **Python SDK** (`deepseek_harness.DeepSeekHarness`) spawning `dsh --profile sdk` over **stdio JSON-RPC** | ✅ near 1:1 replacement surface, but different wire |
| `opencode run --auto -m … --dir … -f …` (deploy changelog) | `dsh --profile headless "job"` (fresh session, final answer to stdout, exit) | ✅ direct analog |
| — | `dsh web` (Web UI) / ACP profiles | not needed by garbanzo |

### 2.1 Python SDK — the headline feature for us

From `python/sdk/README.md` and the user guide:

```python
from deepseek_harness import DeepSeekHarness

with DeepSeekHarness(
    dsh_home="/abs/path/isolated-dsh-home",   # REQUIRED — never reads ~/.dsh
    cwd="/abs/path/workspace",                # agent workspace
    provider="deepseek-official",
    model="deepseek-v4-flash",
    reasoning_effort="max",                   # optional
    max_tokens=49_152,                        # optional per-request cap
) as harness:
    result = harness.run("Say hi.", session_id="example-001")
print(result.final_response)
```

Key facts:

- **Bundled runtime:** the SDK installs and launches the same-version `dsh` binary (`deepseek-harness-runtime-bin` wheel) — "Running the SDK does not require system Node.js." `dsh_bin` can override.
- **Isolation is the design center:** `dsh_home` must be explicit ("The SDK deliberately never discovers `~/.dsh`"). "Use a fresh home when those resources must be isolated, and a fresh session id for independent work." This maps directly onto our per-workspace (micro-apps) and per-run (workflows) isolation needs — one `dsh_home` per workspace, one session id per turn/run.
- **Lazy start, owned subprocess, clean lifecycle:** "starts lazily and reuses its runtime until `close()` or context-manager exit." TS-twin docs document the shutdown ladder (protocol `shutdown` → stdin-EOF → SIGTERM → SIGKILL with grace timers); the SDK owns reaping. Contrast: we hand-rolled all of this in `opencode_process.py` (setsid, PR_SET_PDEATHSIG, pkill belt, `procps` in the Dockerfile).
- **`RunResult`:** `RunResult(session_id, final_response, finish_reason, events, notifications)`; `final_response` = "last committed root-session assistant text in the interval"; `finish_reason` is the `kind` of the last root `turn/end` (`completed`, `max-tokens`, `error`).
- **Live events:** `events` (root session) and `notifications` (root + discovered subagents) come back in wire order; `on_notification` streaming callback exists on `run()`. This is what `microapp_agent.py` would consume instead of opencode's SSE stream.
- **Sessions:** named `session_id` resumes durable conversation + session-owned persistent Bash state ("working directory, exported variables, and shell functions"). Matches our `opencode_session_id` column semantics (VARCHAR(64) is plenty).
- **Timeouts:** `initialize_timeout_seconds` (default 30 s) for the handshake; turns unbounded unless `request_timeout_seconds` set.
- **Customization:** persistent changes go in a `dsh` profile (`dsh plugin --profile sdk add file:/path/to/bundle`); **per-invocation** changes pass YAML **patch files**: `patches=("/abs/first.patch.yml", "/abs/last.patch.yml")` — "become absolute and are forwarded in order after the profile and home patch layers." This is the hook where per-run MCP servers / tool policy would be injected (see §3).
- **Errors:** typed — `JsonRpcResponseError`, `RequestTimeoutError`, `SdkProtocolError`, `TransportClosedError` (with exit code + bounded stderr tail).

### 2.2 SDK wire protocol (what `microapp_agent.py` would translate)

`dsh-sdk-protocol`: newline-delimited JSON-RPC 2.0 over stdio. Three client→server requests (`initialize`, `session/prompt`, `shutdown`) and four server→client notifications:

- `session.event` — every session event, unfiltered ("Notification payloads depend on `SessionEvent` (`dsh-session`), `ContentBlock` (`dsh-llm`) … so the session vocabulary is part of the wire contract")
- `session.status` — whole-agent `running`/`idle` transitions (this is the `done` analog)
- `subagent.started` / `subagent.finished` — descendant lineage (the TS twin auto-scopes to the session tree)

**Known limitations (verbatim, protocol README):**

- "No protocol-version negotiation — the handshake carries only `serverInfo.version` (`0.0.1`, unvalidated by clients); pre-release stance, no compatibility promise."
- **"No cancel or session-close methods — a client abandons a turn by closing the runtime process."**
- Server→client requests are a dead capability reserved "for future approval flows."

**Mapping to our `ChatResponseChunk` envelope:** text deltas, tool calls, tool results, and turn boundaries are all expressible via `session.event` + `session.status` (exact `SessionEvent` payload shapes live in `dsh-session`/`dsh-llm` package docs, not yet extracted — that's prototype work). The `session` chunk type we emit so the Flutter client can abort would map to `(harness instance, session_id)` pairs rather than an HTTP endpoint.

**Abort:** today, garbanzo's `POST /microapps/agent/abort` → `POST /session/{sid}/abort` would become: kill the `DeepSeekHarness` instance (terminate the child runtime). Acceptable for workflows (one harness per run anyway) and workable-but-blunt for micro-apps (one harness per workspace; an abort kills the shared runtime, which then cold-restarts on the next request — persistent Bash state for that session would be lost unless session logs restore it; needs verification).

### 2.3 Headless mode (deploy-changelog analog)

`dsh --profile headless "job"` — "Run one fresh persisted session, print the final answer, and exit." The unofficial community CLI fork adds `--json`, `resume --last`, `--yolo`/`--full-auto`/`--sandbox`/`--ask-for-approval` flags; the official CLI behavior reference owns the exact official flags (not yet fetched). Either way, our `scripts/deploy.sh` changelog generator maps cleanly. (Alternatively the Python SDK with a fresh `dsh_home` + one-shot `run()` would work and gives typed errors + `finish_reason`.)

## 3. MCP — the critical feature for workflows

Garbanzo's workflow runner seeds **per-run MCP server definitions** (stdio command/args/env, http url/headers, per-tool glob allow/deny) from the user's conversation allowance into the agent config. dsh's answer is the `dsh-mcp-client` plugin:

- **Config:** one entry per server — `serverName` (namespace, `[A-Za-z0-9_-]{1,32}`), `transport: stdio` (`command`/`args`/`env`/`cwd`) or `streamable-http` (`url`/`headers`), plus `toolCallTimeoutMs` (default 60 s), `failOnStartupError`, and reconnect policy (backoff 500 ms→30 s, 10 attempts).
- **Tool naming:** `mcp__<serverName>__<tool>` — "the same naming shape Claude Code and Codex use" (and opencode). Same coexistence/conflict guarantees we rely on.
- **Only tools are bridged** — MCP resources and prompts are not supported.
- **stdio env is scrubbed by default:** "ambient names matching `/KEY|PASSWORD|SECRET|TOKEN/i` and ambient `DSH_*` names are dropped" — configured `env` merges on top. *Security upside vs opencode,* but it means our `auth_header` values must ride in the plugin `env`/`headers` explicitly (we already do this — headers/env are explicit in `_opencode_mcp_config`).
- **Per-run injection path:** the plugin config is a Cordis patch — i.e. the `patches=(...)` parameter of `DeepSeekHarness` can carry a per-run YAML patch adding exactly the conversation's MCP servers. This is **the same capability** our seeded `opencode.json` `mcp` block provides, expressed in a different layer. Per-tool whitelisting (our `tools: {"<name>_*": False, "<name>_<tool>": True}` globs) has no documented equivalent in the MCP client README — a gap to resolve in a prototype (may live in the broader tools/policy subsystem).
- **Startup cost:** MCP SDK's 60 s default per `initialize`/`tools/list` bounds activation — comparable to our 60 s opencode readiness budget, and it can delay the first turn.

## 4. Providers & models (Ollama compatibility)

- Default composition registers `deepseek-official` (`DEEPSEEK_API_KEY`, `DEEPSEEK_BASE_URL` override; SDK accepts `base_url`/`api_key` explicitly).
- **Custom OpenAI-compatible providers:** `llm-pi-ai` plugin with `settings.yaml` routes — `providers: { my-gateway: { apiKeyEnv, api: openai-completions, baseURL: https://…/v1, models: [{id: …}] } }`; "Fetch available models" discovery against `GET /models`; documented `compat` switches for non-OpenAI quirks (`supportsDeveloperRole: false`, `maxTokensField: max_tokens`, `thinkingFormat: deepseek`). **No Ollama-specific mention** in the docs, but Ollama is an OpenAI-compatible endpoint — the provider guide's own examples use local gateways; the user-guide example even shows `DEEPSEEK_BASE_URL=http://127.0.0.1:8000/v1` for a proxy. Our `MICROAPPS_OPENCODE_MODEL=ollama/glm-5.3:cloud` would become a pi-ai route against `settings.ollama_base_url + /v1`. **One risk to verify:** the pi-ai catalog-resolution quirks the community handbook documents (custom providers colliding with catalog entries and silently sending Anthropic-style `/messages`, `developer`-role rejections on some gateways). Ollama's `/v1` is well-trodden OpenAI-compat territory, so likely fine, but the compat switches exist precisely because "most OpenAI-compatible gateways refuse at least one thing OpenAI accepts."
- **Per-run model selection:** `provider`/`model`/`reasoning_effort`/`max_tokens` are SDK constructor/initialize parameters — no config-file rewrite needed per run (today we re-derive the seeded `opencode.json` from `MICROAPPS_OPENCODE_MODEL`). Model changes "take effect on the next request" in web mode.
- `settings.yaml` lives under `$DSH_HOME` — with per-workspace homes, per-workspace model/provider settings come for free.

## 5. Permissions & sandbox (detached-run safety)

- Permission modes exist (`--yolo`, `--full-auto`, `--sandbox`, `--ask-for-approval` documented in the CLI reference/permission-presets package; `minimal.py` example uses `danger-full-access` with a "run it only inside a disposable checkout or container" warning).
- The minimal composition logs "sandbox-policy facts … as runtime user context rather than appended to the system prompt."
- The SDK profile composition and its approval policy are chosen by the profile's `cordis.yml` — i.e. **we control the composition** (we'd ship our own profile/patch pinning an unattended-safe policy, the equivalent of our `DEFAULT_PERMISSION {"edit","bash","webfetch": "allow"}` envelope + `opencode.json` permission-block injection logic in `workflow_runner._ensure_permission_envelope`).
- dsh's model of this is more granular than opencode's (per-tool/per-effect policy in the tool-execution pipeline: "approval, guards, and tool effects"), but exact policy configuration is plugin-level detail to work out in a prototype.

## 6. How the replacement would be built (if we did it)

**Micro-apps (long-lived per workspace):**

1. `MicroappWorkspaceManager.ensure()` creates `<worktrees>/<slug>/` git worktree as today, plus a `dsh-home/` directory per workspace.
2. Replace `_start_opencode` with a lazily-started `DeepSeekHarness(dsh_home=…, cwd=ws.path, provider="ollama", model=…, patches=(workspace-patch,))`; keep one harness per workspace (like today's one serve process).
3. `MicroappAgent.stream_instruction` becomes an async wrapper around `harness.run(..., on_notification=…)` translating `session.event`/`session.status` notifications into `ChatResponseChunk`s (chunk/thinking/tool_call/tool_result/done). The SSE relay to Flutter (`_sse` in `microapps.py`) and the `micro_app` chat tool forwarding stay identical — only the source of chunks changes.
4. Abort = close the harness (kill child), respawn on next instruction. Session logs (`session-persistence-jsonl`, zstd-compressed) may restore conversation state across restarts — verify.
5. `_seed_opencode_config`/`opencode_config.py` become patch-YAML generation (provider route in `settings.yaml` + optional per-workspace MCP patch). `CLAUDE.md`/`AGENTS.md` instructions are read from the workspace cwd by dsh itself.

**Workflows (one-shot per run):**

1. `workflow_runner._run` creates a fresh `dsh_home` (or uses the run dir), a patch YAML carrying the conversation's MCP servers, then `asyncio.to_thread`-style drive of `harness.run(instruction, session_id=run_id)` with `on_notification` → `service.append_progress` (same 1 s flush/coalescing machinery).
2. `MAX_RUN_SECONDS` becomes `request_timeout_seconds` (cleaner than our `asyncio.timeout` belt).
3. `session` chunk handling → store dsh session id in `opencode_session_id` (rename column to `agent_session_id` via migration — provider-neutral).
4. `_TOOL_RESIDUE` diff hygiene: `.opencode/` entry becomes unnecessary (state lives in `dsh_home`, outside the workdir — same win as Hermes); keep the rest.
5. `terminate(proc)`/`pkill` belt becomes `harness.close()` — the SDK's own EOF→SIGTERM→SIGKILL ladder replaces our hand-rolled process management. `procps` may stay for dev servers.

**Deploy changelog:** swap `opencode run` for `dsh --profile headless` (or a small Python script using the SDK) behind the existing `command -v` fallback guard.

**Open items a prototype must answer:** exact `SessionEvent` payload shapes for text/tool-call streaming; per-tool MCP whitelisting equivalent; abort semantics for shared workspace harnesses; Ollama compat verification; memory footprint of a `dsh --profile sdk` child per workspace; whether `DSH_HOME` relocation per instance has the same "single-writer" caveats the Web mode documents for session roots.

## 7. Recommendation

1. **Keep opencode as the in-app agent for now.** dsh is 2 weeks old, self-declared developer preview with guaranteed breaking changes, and its SDK protocol is explicitly "pre-release stance, no compatibility promise." Migrating ~8 backend files + Flutter SSE consumers + a DB column onto that now would mean chasing breakage.
2. **The Python SDK model is the right long-term shape for us** — explicit `dsh_home` per workspace/run, bundled runtime (no system Node), typed errors, owned subprocess lifecycle. It fixes real pain points we hand-rolled (port management, readiness probes, pkill cleanup, state leakage into diffs). Track dsh's exit from developer preview + the addition of a wire-level cancel method as the trigger conditions to revisit.
3. **Cheap preparatory refactor (optional, separate task):** make our agent seam provider-neutral — rename `MICROAPPS_OPENCODE_BIN`/`MICROAPPS_OPENCODE_MODEL` → `MICROAPPS_AGENT_BIN`/`MICROAPPS_AGENT_MODEL`, `opencode_session_id` → `agent_session_id`, and abstract `MicroappAgent` behind a small protocol (`stream_instruction`/`abort`). This was also the conclusion of the Hermes comparison (§8); it makes any future swap — dsh, Hermes, or otherwise — a client-layer change instead of a codebase-wide rename. Not done here (research-only, as requested).
4. **Do not adopt for the deploy changelog either, yet:** the headless profile is the same pre-release risk for less benefit. Revisit together with the main migration.

## 8. For the record: the earlier (mistaken) Hermes comparison

The first link I was given (`api-docs.deepseek.com/.../hermes/`) was DeepSeek's integration guide for **Hermes Agent by Nous Research** — a different agent entirely, which DeepSeek's docs merely list as one of many agents you can point at their API. Since the confusion may recur, the summary is retained here:

- **Hermes ≠ DeepSeek.** Open-source personal agent (Nous Research, MIT): CLI/TUI/desktop, messaging gateway (Telegram/Discord/…), cron, kanban, 70+ tools. Heavy footprint: Python 3.11 venv + Node 26 + ripgrep + ffmpeg; 1–4 GB RAM per instance; official Docker image exists.
- **Server mode naming trap:** `hermes serve` is the desktop backend (port 9119), NOT the API. The OpenAI-compatible surface is the **API server inside `hermes gateway`** (`API_SERVER_ENABLED=true`, port 8642, bearer auth mandatory even on loopback) — Runs API (`/v1/runs` + events SSE + stop/approval/steer), Sessions API (`/api/sessions/{id}/chat/stream` emitting `assistant.delta`, `tool.started`, `tool.completed`, `run.completed`), `/health` readiness, per-request `model`/`provider` fields.
- **Isolation:** profiles (`hermes profile create`, `~/.hermes/profiles/<name>/`, own port+key); no cwd-level config file (only `~/.hermes/config.yaml`); `--ignore-user-config`/`--ignore-rules`/`--safe-mode`/`--in <dir>` per-invocation isolation flags.
- **MCP:** profile-global `mcp_servers` in `config.yaml` only — **no per-session/per-workdir MCP injection** (garbanzo's per-run workflow MCP seeding would need a profile-per-workspace workaround). Per-server include/exclude glob filters, `trust: untrusted` tiers, OAuth 2.1, mTLS.
- **Providers:** `provider: custom` + `base_url` for local Ollama; per-request model/provider on runs/session-chat endpoints.
- **Verdict then:** deploy-changelog replacement easy; in-app agent replacement a weeks-long rewrite (profile-per-workspace MCP workaround, heavy footprint at our per-user fan-out, undocumented SSE payload shapes, unspecified non-interactive approval behavior). Compared side by side, **dsh's Python SDK model is a materially better fit for garbanzo than Hermes's gateway+profiles model** — dsh was designed for exactly our embedding pattern (owned subprocess, explicit home, per-invocation patches).

## 9. Sources

**DeepSeek Harness (official):**

- Quickstart (Web UI): <https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart>
- Model/provider configuration: <https://deepseek-harness.github.io/deepseek-harness/en/guide/providers>
- Python SDK guide: <https://deepseek-harness.github.io/deepseek-harness/en/guide/python-sdk>
- Repo README (run modes, preview warning): <https://github.com/deepseek-ai/deepseek-harness>
- CLI launcher (profiles, headless/sdk/acp modes): <https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.md>
- Python SDK reference (`DeepSeekHarness`, `dsh_home`, patches, timeouts): <https://github.com/deepseek-ai/deepseek-harness/blob/master/python/sdk/README.md> and `python/README.md`
- SDK wire protocol (methods, notifications, no-cancel limitation): <https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/sdk/protocol/README.md>
- TypeScript client SDK (twin; lifecycle ladder, error types, known limitations): <https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/sdk/client/README.md>
- MCP client plugin (config, naming, scrubbing, reconnect): <https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/mcp/mcp-client/README.md>
- Session data plane (JSONL/SQLite persistence, projections, telemetry): <https://github.com/deepseek-ai/deepseek-harness/tree/master/packages/session>
- Community handbook (rc/alpha runbooks, ecosystem counts, headless/CLI guides): <https://github.com/sandbaseai/deepseek-harness-handbook>
- Unofficial community CLI fork (exec/--json/--yolo flags — unofficial): <https://github.com/peiyuwang54/deepseek-harness-cli>

**Hermes Agent (the earlier mistaken subject, kept for the record):** <https://api-docs.deepseek.com/quick_start/agent_integrations/hermes/>, <https://hermes-agent.nousresearch.com/docs/> (CLI commands, architecture, programmatic integration, provider runtime, API server, MCP config reference).

**garbanzo-ai integration surface (what would be replaced):** `backend/app/services/{opencode_process,opencode_config,workflow_runner,workflow_service,microapp_agent,microapp_workspace,microapp_chat_tool}.py`, `backend/app/api/v1/endpoints/{microapps,workflows}.py`, `backend/migrations/032_workflow_runs.sql`, `scripts/deploy.sh`, `backend/Dockerfile`, `deploy/docker-compose.yml`, `docs/{architecture,api,database,environment}.md`.