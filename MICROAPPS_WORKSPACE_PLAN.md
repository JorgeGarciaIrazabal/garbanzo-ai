# Micro-Apps Agentic Workspace — Detailed Execution Plan

> Status file: checkboxes are ticked as work lands. Spans two repos:
> **`~/code/micro-apps`** (apps, skills, dev server) and **`~/code/garbanzo-ai`** (backend workspace manager + Flutter UI).

## Progress (live)

- **Phase 1 (micro-apps foundation): DONE & verified** — dynamic CI + deployed-landing CSS/JS fix, `.gitignore` fix, Playwright specs de-staled, `houses/` + file-backed embed (`?project=&save=1&embed=1`) in house-designer, dev-server `/__save` + `__houses` + houses watcher. 9/9 Playwright green, prod build clean, full browser round-trip (load/save/agent-edit-reload/undo) verified.
- **Phase 2 (skills): DONE** — `house-design` extended; `microapp-new/publish/revert/embed` written; symlinked into `.opencode/skills/`; `opencode.json` (Ollama-cloud) + `AGENTS.md` + `CLAUDE.md`. Caveat: the standalone `opencode run` CLI edit test was too slow/flaky on Ollama *cloud* models to confirm here (opencode loads config+skills fine; it's a model-speed matter) — validate in Phase 5, pick a faster local coding model if needed.
- **Phase 3 (garbanzo backend): DONE & verified** — 19 new tests pass (434 total), app imports, 11 routes registered. See "Backend delivered" below.
- **Phase 4 (garbanzo frontend): DONE & verified** — `lib/features/microapps/` (models, service+`MicroappApi` interface, provider, platform-adaptive `MicroAppView` with web-iframe/native-webview/desktop-fallback via conditional import, two pages, drawer entry). `flutter analyze` clean, `flutter build web` compiles the iframe code, 4 provider stream/abort tests pass. Added `web: ^1.1.0` dep + `dev_port` to the backend `WorkspaceStatus` (so the embed URL uses the API-base host — required for Android).
- **Phase 5 (E2E): PASSED (live agent edit) + deterministic checks.** Confirmed: Phase-1 file→reload loop in a real browser (9 Playwright tests); backend 434 tests + real-repo registry/houses parse + routes registered; frontend web build + provider tests. **Live agent E2E confirmed** — drove the real `microapp_agent.py` against a live `opencode serve` in the repo: the agent invoked the `house-design` skill → `read` the house file → `write` a new window (valid geometry) → the file changed and **passed both validator and layout linter**; the SSE relay emitted the full `session→thinking→tool_call→tool_result→chunk→done` sequence. See "Operational findings" below.

### Operational findings (from the live E2E)
- **Ollama *cloud* models were blocked by the account's weekly usage limit** (`you have reached your weekly usage limit`) — this, not any code issue, is why cloud models stalled (opencode leaves the assistant message empty). Check quota before using `:cloud` models.
- **opencode only accepts models listed in `opencode.json`'s `provider.models`** — an unlisted model returns `Model not found` (cleanly surfaced as an `error` chunk). `opencode.json` now lists local `qwen3.6:35b-a3b-q8_0` + `qwen3:4b` alongside the cloud models.
- **CPU-only inference**: the 35B local model is impractically slow; **`qwen3:4b` completed the full read→edit→validate loop** and produced a valid edit. The backend's default `microapps_opencode_model` can be pointed at whatever model the user's box runs well.
- **Not committed/pushed** in either repo — all reversible, awaiting review.

### Frontend delivered
`lib/features/microapps/`: `models/micro_app.dart`; `services/microapp_service.dart` (`MicroappApi` interface + `MicroappService` + `MicroappApiException`; composes the embed URL `<host>:<devPort>/micro-apps/house-designer/?embed=1&project=/micro-apps/<house>&save=1`, using API-base host for non-loopback devices); `providers/microapp_provider.dart`; `widgets/micro_app_view{,_web,_native}.dart` (conditional import `if (dart.library.js_interop)`); `pages/micro_apps_page.dart` + `micro_app_workspace_page.dart`; drawer ListTile in `pages_section.dart`. Test `test/microapps/microapp_provider_test.dart`. Reuses the chat `ChatResponseChunk` + `parseSseChunks`.

### Backend delivered (contract the frontend targets)
Files: `backend/app/services/microapp_{workspace,agent,registry}.py`, `endpoints/microapps.py`, `schemas/microapp.py`, tests `test_microapp_{workspace,agent}.py`; modified `config.py` (+6 `microapps_*` settings), `schemas/chat.py` (added `tool_execution`,`session` chunk types), `router.py`, `main.py` (shutdown), `.env.example`.
Endpoints under `/api/v1/microapps`: `POST/GET/DELETE /workspace`, `GET /apps`, `GET/POST /houses`, `POST /agent/chat` (SSE), `POST /agent/abort`, `GET /changes`, `POST /publish`, `POST /revert`. SSE emits `ChatResponseChunk` with types `session`(first, has session_id)→`chunk`/`thinking`/`tool_call`/`tool_result`→`done`→`error`. Feature-off ⇒ 404; business errors ⇒ 409. Workspace seeds `opencode.json` into each worktree; publish rebases onto origin/main and pushes `HEAD:main`.

## Vision

Garbanzo-ai becomes a host for the user's micro-apps:

1. Garbanzo backend maintains a **git worktree of `~/code/micro-apps` per user** and runs the micro-apps **dev server** (`scripts/dev-server.js`, HMR) inside it.
2. The Flutter app **displays** micro-apps as dumb views (web: iframe; Android: WebView; desktop: open-in-browser). No runtime bridge — the display knows nothing about app state.
3. An **opencode headless agent** (Ollama cloud models; same pattern as `~/code/garbanzo-books/ui/opencode_client.py` + `ui/chat.py`) runs in the worktree and **edits files directly** — app source code or git-tracked `houses/*.house.json` — guided by the repo's **skills** (shared `.claude/skills/` ⇄ `.opencode/skills/`, same SKILL.md format).
4. The dev server hot-reloads source edits; a small file-watcher reloads house files; the user sees changes live.
5. **Publish** = validate → commit → rebase on main → push → GitHub Pages CI. **Revert** = scoped git restore. Both are backend endpoints *and* skills.
6. House-designer is the flagship: houses live as files; the embedded app loads them via `?project=` and auto-saves manual edits back via a dev-server `/__save` endpoint, so manual and AI edits share one source of truth with git history.

Language: instructions can be English or Spanish — the agent mirrors the user's language; house-designer UI itself is already EN+ES.

---

## Part A — micro-apps repo

### A1. Hygiene + dynamic CI  ✅ when all boxes ticked

- [ ] **A1.1** `tools/playwright-check/app.spec.mjs`: replace stale `planner5d` references with `house-designer`; run the harness green (baseline trust).
- [ ] **A1.2** `.github/workflows/deploy.yml`: replace the 4 hardcoded "Install & build X" steps and the hardcoded assemble block with a dynamic loop:
  ```yaml
  - name: Install & build all apps
    run: |
      set -e
      for app in apps/*/; do
        name=$(basename "$app")
        echo "=== $name ==="
        (cd "$app" && npm ci && npm run build)
      done
  - name: Assemble site
    run: |
      set -e
      mkdir -p _site
      cp index.html style.css script.js registry.json _site/
      [ -d houses ] && cp -r houses _site/houses || true
      for app in apps/*/; do
        name=$(basename "$app")
        mkdir -p "_site/$name"
        cp -r "$app/dist/." "_site/$name/"
      done
  ```
  Fixes the live bug: deployed landing currently lacks `style.css`/`script.js` (only `index.html` was copied).
- [ ] **A1.3** `.gitignore`: add `/casa-prefab-madrid/`, `/house-designer/`, `/.worktrees/`; then `git rm -r --cached casa-prefab-madrid house-designer` (root built copies only, NOT `apps/*`).

### A2. Git-tracked houses + file-based loading in house-designer

- [ ] **A2.1** Create `houses/` at repo root with one starter file (validated): `houses/sample-family-home.house.json` (generate from the clean `tinyCabin()`/samples, run `validate.mjs` + `lint-layout.mjs`).
- [ ] **A2.2** `apps/house-designer/src/App.jsx` — URL-driven project mode:
  - Parse `new URLSearchParams(location.search)`: `project` (URL, same-origin relative expected), `save` (`1`), `embed` (`1`).
  - Boot: if `project` present → `fetch(projectUrl)` → `deserialize` (tolerant) → use as initial project (skip localStorage slot); on fetch/parse failure show toast + fall back to `createProject`.
  - Persistence in project-mode: keep localStorage autosave (harmless) **and**, when `save=1`, debounce (~800 ms) `PUT ${saveEndpoint}?path=<project param>` with `serialize(project)` body. Save endpoint = same origin `/__save`. Non-2xx → one toast, don't spam.
  - **External reload**: subscribe to the dev server's SSE reload channel (see A2.4); on `houses-changed` event for our path — and only if the change wasn't our own save (compare last-saved serialization) — refetch and `commit()` the new project (undoable, so the user can Ctrl+Z an AI edit).
  - `embed=1` → `document.documentElement.dataset.embed = '1'`.
- [ ] **A2.3** `apps/house-designer/src/App.css`: `html[data-embed="1"]` hides Google Drive controls + Open/Save-file buttons (file is the persistence); keeps 2D/3D, tools, undo/redo, floor bar.
- [ ] **A2.4** `scripts/dev-server.js` extensions (root dev host, port 8000/`PORT`):
  - `PUT/POST /__save?path=houses/<name>.house.json` — sanitize: resolve inside repo root, must match `houses/*.house.json`, body must `JSON.parse`, atomic write (tmp+rename). Reply JSON `{ok:true}`.
  - `GET /__houses` — list `houses/*.house.json` with mtime/size (used by garbanzo + test page).
  - Watch `houses/` (fs.watch, debounced): broadcast `{type:'houses-changed', path}` on the existing SSE reload channel; skip events caused by `/__save` writes within ~1s (echo suppression).
- [ ] **A2.5** `registry.json` (repo root, deployed):
  ```json
  { "version": 1, "apps": [
    { "id": "house-designer", "name": "House Designer", "icon": "🏠", "path": "house-designer/",
      "projectParam": true, "dataDir": "houses/", "dataExt": ".house.json",
      "suggestions": ["Add a window to the living room", "Añade un baño en la planta de arriba", "Make the kitchen bigger"] },
    { "id": "andalucia-scouting-2026", "name": "Andalucía Scouting 2026", "path": "andalucia-scouting-2026/" },
    { "id": "casa-prefab-madrid", "name": "Casa Prefab Madrid", "path": "casa-prefab-madrid/" },
    { "id": "clara-summer-camps-madrid", "name": "Clara Summer Camps", "path": "clara-summer-camps-madrid/" } ] }
  ```
- [ ] **A2.6** Verification (manual, chrome-devtools MCP): `make dev` → open `http://localhost:8000/micro-apps/house-designer/?project=/micro-apps/houses/sample-family-home.house.json&save=1&embed=1` → house renders, chrome hidden; move a sofa → file mtime changes & content updates; edit the file on disk (sed a wall coord) → app refetches & shows it; Ctrl+Z undoes it.
- [ ] **A2.7** Playwright: `tools/playwright-check/project-file.spec.mjs` covering load-from-file, save-back, external-change reload, undo.

### A3. Skills + agent config (micro-apps repo)

Author under `.claude/skills/<name>/SKILL.md`; `ln -s ../../.claude/skills/<name> .opencode/skills/<name>` (opencode uses the same format — precedent: `.opencode/skills/websearch/`).

- [ ] **A3.1** Extend `house-design` skill: `houses/` convention; the `?project=&save=1` workflow; **mandatory gates**: run `node .claude/skills/house-design/validate.mjs <file>` and `node .claude/skills/house-design/lint-layout.mjs <file>` after every house edit and fix issues before finishing; never rewrite a house from scratch when asked for an incremental change (edit the existing JSON). Symlink into `.opencode/skills/`.
- [ ] **A3.2** `microapp-new`: scaffold `apps/<name>/` (package.json pinned react ^19 / vite ^8 / plugin-react ^6, `vite.config.js` with `base:'/micro-apps/<name>/'`, index.html, src/main.jsx, src/App.jsx, src/App.css), `npm install`, landing card in root `index.html` (+ bump hero `data-target`), `APP_DETAILS` entry in root `script.js`, `registry.json` entry, verify on dev server. (CI is dynamic after A1.2 — no workflow edit.)
- [ ] **A3.3** `microapp-publish`: preflight (`npm run build` for touched apps; validate+lint touched houses; `git status` must not include root built copies), commit with descriptive message, `git fetch` + rebase onto `origin/main` (worktree branches), push; `gh run watch` until Pages deploy green; verify the deployed URL. Never force-push; on rebase conflict stop and report.
- [ ] **A3.4** `microapp-revert`: show `git status --porcelain` + short diff first; revert scoped paths (`git checkout -- <paths>` / `git clean -fd <paths>`) or `git revert <sha>`; confirm scope; never touch other branches/worktrees.
- [ ] **A3.5** `opencode.json`: add the Ollama-cloud provider/models block (copy from `~/code/garbanzo-books/opencode.json`, keep `kimi-k2.7-code:cloud` + `glm-5.2:cloud` etc.), pick default coding model, `"instructions": ["CLAUDE.md"]`, `"permission": {"edit":"allow","bash":"allow","webfetch":"allow"}`.
- [ ] **A3.6** `CLAUDE.md`/`AGENTS.md`: houses workflow section, skills index, dev-server endpoints, "the user may be watching the app live via garbanzo — after house edits the watcher reloads it; after source edits HMR applies".
- [ ] **A3.7** Verify agent E2E in the repo: `opencode run "add a window to the north wall of the living room in houses/sample-family-home.house.json"` → skill used, validator+linter pass, file valid.

### A4. Publish Part A

- [ ] **A4.1** Commit + push micro-apps `main` (use the microapp-publish skill flow manually = dogfood), watch CI, verify: landing has CSS/JS, `registry.json` + `houses/` served, `?project=` works read-only on GitHub Pages.

---

## Part B — garbanzo-ai

### B1. Backend — workspace manager

- [ ] **B1.1** Config (`backend/app/core/config.py` + `.env.example` docs): `MICROAPPS_REPO_PATH` (default empty ⇒ feature disabled/hidden), `MICROAPPS_DEV_PORT_BASE=8100`, `MICROAPPS_OPENCODE_BIN="opencode"`, `MICROAPPS_PUBLISH_REMOTE="origin"`, `MICROAPPS_WORKTREES_DIR=".worktrees"`.
- [ ] **B1.2** `backend/app/services/microapp_workspace.py` — `MicroappWorkspaceManager` (module-level singleton, like scheduler):
  - `ensure(user_email) -> Workspace`: slugify email; `git worktree add <repo>/.worktrees/<slug> -B garbanzo/<slug>` if missing; ensure `node_modules` per app (`npm install --prefer-offline`, emit progress); allocate dev port (base + stable index); spawn dev server (`node scripts/dev-server.js`, env `PORT`, cwd=worktree); spawn `opencode serve --hostname 127.0.0.1 --port <rand>` cwd=worktree; poll `/config` ready (≤60 s).
  - Subprocess safety: `os.setsid` + `PR_SET_PDEATHSIG=SIGKILL` preexec + atexit + pkill-by-port belts (port of `garbanzo-books/ui/opencode_client.py`).
  - `status(user)`, `stop(user)` (kill both procs, keep worktree), `stop_all()` on app shutdown (wire into FastAPI lifespan next to scheduler shutdown).
  - Git ops: `changes(user)` (porcelain + numstat vs merge-base with main), `publish(user, message)` (validate houses via `node .claude/skills/house-design/validate.mjs`, commit-all, fetch, rebase onto `origin/main`, push branch → **push to main**: fast-forward main to the branch after rebase (single-remote personal repo) — implement as: rebase branch onto origin/main, push `HEAD:main`), `revert(user, paths|all)`.
- [ ] **B1.3** `backend/app/services/microapp_agent.py` — opencode relay (port of `garbanzo-books/ui/chat.py`):
  - `stream_instruction(workspace, instruction, session_id?) -> AsyncIterator[ChatChunk]`; create session (`POST /session`) if needed; `POST /session/{id}/prompt_async`; subscribe `GET /event` (httpx-sse or manual line parsing — httpx only, no new deps if possible); translate: `message.part.updated` text → `chunk`, reasoning → `thinking`, tool events → `tool_call`/`tool_execution`/`tool_result`, `session.idle` → `done`, `session.error` → `error`; watchdog (no events + no process ⇒ error; long silence ⇒ keep-alive comment); `abort(workspace, session)` → `POST /session/{id}/abort`.
  - Chunk shapes reuse `app/schemas/chat.py` chunk envelope so the SSE wire format matches `/chat/...` exactly.
- [ ] **B1.4** `backend/app/schemas/microapp.py`: `WorkspaceStatus{state, dev_url, branch, opencode_ready, setup_progress}`, `MicroAppInfo` (registry entry passthrough), `HouseFile{path,name,modified_at,size}`, `ChangesSummary{files:[{path,status,plus,minus}], ahead, behind}`, `PublishRequest{message?}`, `PublishResult{commit, run_url?}`, `RevertRequest{paths?}`, `AgentChatRequest{instruction, session_id?}`.
- [ ] **B1.5** `backend/app/api/v1/endpoints/microapps.py` (+ register in `router.py`, prefix `/microapps`, tag `microapps`): `POST /workspace`, `GET /workspace`, `DELETE /workspace`, `GET /apps`, `GET /houses`, `POST /houses` (create from template), `POST /agent/chat` (SSE), `POST /agent/abort`, `GET /changes`, `POST /publish`, `POST /revert`. All behind `get_current_user`; 404-style feature-disabled response when `MICROAPPS_REPO_PATH` unset.
- [ ] **B1.6** Tests: `backend/tests/test_microapp_workspace.py` — worktree ensure/idempotent, port allocation, changes/publish/revert against a **temp git repo fixture** (no network; stub remote with a local bare repo); subprocess spawn mocked. `backend/tests/test_microapp_agent.py` — event translation from a fake opencode SSE stream (text/reasoning/tool/idle/error), abort path. `just be-test`, `just be-lint`.

### B2. Frontend — Flutter feature module

- [ ] **B2.1** `lib/features/microapps/models/` — plain Dart or freezed (match repo convention): `MicroAppInfo`, `HouseFile`, `WorkspaceStatus`, `ChangesSummary`. Run build_runner if freezed; commit generated files.
- [ ] **B2.2** `lib/features/microapps/services/microapp_service.dart` — REST + SSE via `ApiClient` (reuse `parseSseChunks` from `chat_service.dart`; agent chat = `streamPost`-style).
- [ ] **B2.3** `lib/features/microapps/widgets/micro_app_view.dart` — platform-adaptive dumb display of a URL with `reload()`:
  - web: conditional-import pair (`micro_app_view_web.dart` with `dart:ui_web` `platformViewRegistry.registerViewFactory` + iframe element via `package:web`; `micro_app_view_stub.dart` otherwise).
  - Android: `webview_flutter` (`JavaScriptMode.unrestricted`, pattern from `mermaid_diagram.dart`).
  - Linux/other: card + "Open in browser" (`url_launcher` — add dep if absent).
- [ ] **B2.4** `lib/features/microapps/providers/microapp_provider.dart` — workspace lifecycle + polling during setup; app/house lists; agent stream state (reuse `ChatResponseChunk`); changes summary refresh after agent `done` + after manual-edit debounce; publish/revert with confirmation; view-reload trigger on agent `done`.
- [ ] **B2.5** Pages: `micro_apps_page.dart` (workspace card + app grid from registry + house picker for apps with `dataDir`); `micro_app_workspace_page.dart` (responsive: app view + agent rail — instruction composer EN/ES, suggestion chips, streaming narration reusing existing chat message/tool widgets, abort, changes bar with Publish/Revert dialogs). Navigation ListTile in `lib/features/settings/widgets/drawer_sections/pages_section.dart` (visible only when backend reports feature enabled).
- [ ] **B2.6** `just fe-lint`, `just fe-test`; widget test: agent rail states (streaming/done/error) + publish dialog with mocked service.

### B3. E2E verification

- [ ] **B3.1** Web: `just dev-web` (+ `MICROAPPS_REPO_PATH=../micro-apps` in backend/.env) → Micro-Apps → workspace boots (worktree + dev host + opencode) → House Designer + sample house renders → manual edit persists to worktree file → EN instruction ("add a window…") applies live → ES instruction ("añade un baño…") applies live → in-app Ctrl+Z undoes AI edit → source-code instruction ("make the topbar green") applies via HMR → Changes bar → Revert restores → re-apply → Publish → CI green → change live on GitHub Pages.
- [ ] **B3.2** Android: `just dev` → same checklist in WebView (dev host reachable via LAN IP).
- [ ] **B3.3** Failure paths: opencode down → clear error in rail; invalid house JSON from agent → validator gate catches (agent fixes or reports); publish rebase conflict → surfaced, no push.

## Decisions log

- Runtime bridges (postMessage iframe, then backend WS) rejected by user — **files + git + dev server** is the architecture.
- Agent runtime: **opencode headless via Ollama cloud** (garbanzo-books pattern), NOT claude CLI — skills still load (opencode supports the same SKILL.md format).
- Houses are **git-tracked files**, source of truth for both manual (app auto-save-back) and AI edits.
- Multi-user: git worktree per user under `micro-apps/.worktrees/<slug>`, branch `garbanzo/<slug>`; publish rebases onto main and pushes `HEAD:main`.
- Publish/revert: deterministic backend git endpoints for the UI buttons; skills exist so the agent can also be asked to publish/revert conversationally.

## Part C — Chat-integrated redesign (supersedes the separate Micro-Apps page)

**User directive:** reuse the main AI chat window (no second chat UI, no separate Micro-Apps page). When the chat LLM detects the user wants a micro-app, a **panel opens to the right** of the chat showing the live app. Fully integrated.

**Decisions (confirmed):**
- **Trigger:** the normal chat model calls a first-class `house_designer` tool when it detects intent (primary), **plus** a manual 🏠 affordance in the composer as a reliable fallback / on-demand open.
- **Routing:** the chat model decides **per message** — every message goes to the chat model, which re-calls the tool for edit-shaped messages; general chat and house edits mix freely in one thread.
- Edits are still executed by **opencode** (reuse `microapp_agent`); the chat tool executor relays opencode's activity into the same turn as nested tool progress.
- The old `MicroAppsPage` / `MicroAppWorkspacePage` / drawer entry / separate agent rail are **removed**. `micro_app_view.dart`, the models, the workspace manager, and the workspace/houses/publish/revert endpoints are **kept**.

### C1. Backend — house_designer as a native chat tool
- [x] **C1.1** Native tool descriptor `house_designer(instruction: str, house?: str)` injected into the chat tool list in `chat_service._resolve_tools_for_conversation` (only when `microapps_repo_path` set). Coexists with MCP tools.
- [x] **C1.2** Executor branch in `chat_service._execute_tool_call`: ensure the user's workspace (idempotent), pick/create the target house, relay the instruction to `microapp_agent.stream_instruction`, translate its `ChatResponseChunk`s → `ChatChunk`s (passthrough thinking/tool_call/tool_result/text) so they stream inside the turn.
- [x] **C1.3** Emit a **panel signal** so the frontend reveals the view: a `ChatChunk` carrying `metadata={"microapp": {"action":"open","app":"house-designer","house":<file>,"url":<embed dev url>}}` (host-resolved like the API base for Android). Bump/refresh on tool `done`.
- [x] **C1.4** Per-conversation "active house" memory (so follow-up edits without an explicit house keep editing the same one) — store on the conversation (JSONB meta) or a keyed in-memory map.
- [x] **C1.5** Keep workspace/houses/publish/revert/status endpoints (used by the manual open + panel action bar). Tests: tool descriptor present only when enabled; executor translates a fake opencode stream + emits the open signal.

### C2. Frontend — right panel in the main ChatPage
- [x] **C2.1** `MicroappPanelController` (or extend `ChatProvider`): state `{open, app, house, url, reloadCounter}`; opens on the `microapp` metadata signal; `reloadCounter++` on turn `done` to refresh the view (belt for the dev-server watcher).
- [x] **C2.2** `ChatPage` layout: wide screens → `Row(chat, VerticalDivider, panel)` with a draggable/collapsible width; narrow (Android) → panel as a full-height overlay / toggle (chat ⇄ house) since split isn't usable. Reuse `micro_app_view.dart`.
- [x] **C2.3** Composer 🏠 button: ensures workspace + opens the panel with a house picker (manual fallback), independent of the LLM.
- [x] **C2.4** Panel chrome: house name + picker, a **reload**, a **close**, and the **Publish/Revert** action bar (reuse the dialogs already built).
- [x] **C2.5** Remove `MicroAppsPage`, `MicroAppWorkspacePage`, the drawer ListTile; keep/trim the service to what the panel + manual open need.
- [x] **C2.6** `just fe-lint`, `just fe-test`; widget test: panel opens on a mocked `microapp` signal; manual button opens it.

### C3. E2E (integrated)
- [ ] **C3.1** In the main chat: "add a window to the salón" → model calls `house_designer` → panel opens right → window appears; then a general question answers normally; then "añade un baño arriba" edits again. Manual 🏠 open works. Publish/Revert from the panel. Android overlay variant.

**Risk:** detection depends on the conversation model being a competent tool-caller. Mitigated by the manual 🏠 button and by ensuring the default micro-app-capable model is tool-capable (kimi/qwen tool-calling already proven).
