# AGENTS.md — Garbanzo AI

High-level guide for AI agents working in this repo. Read this first, then consult the detailed rules in `.cursor/rules/`.

---

## Cursor Rules

Persistent guidance lives in `.cursor/rules/`. Both rules have `alwaysApply: true` and are injected into every session.

| Rule file | What it covers |
|-----------|---------------|
| `project-overview.mdc` | Stack, directory layout, `just` commands, auth flow, Flutter web quirks |
| `e2e-testing.mdc` | How to start the stack, interact with the browser MCP, verify API calls, stop processes |

---

## Available MCP Servers

Three MCP servers are enabled for this project. Prefer MCP tools over raw shell commands whenever they cover the task.

### 1. `cursor-ide-browser` — Browser automation (Playwright-style)

Controls the **Cursor built-in browser tab** (the same tab visible in the IDE). Use this for navigating, clicking, and asserting on any web UI.

| Tool | Purpose |
|------|---------|
| `browser_navigate` | Go to a URL |
| `browser_snapshot` | Get the current accessibility tree — **call this before every interaction** |
| `browser_click` | Click an element by ref |
| `browser_fill` | Clear + set a field value (preferred over `browser_type` for forms) |
| `browser_type` | Append text to a focused field |
| `browser_fill_form` | Fill multiple fields at once |
| `browser_press_key` | Send a key (Tab, Enter, Escape, …) |
| `browser_scroll` | Scroll the page |
| `browser_wait_for` | Wait for a selector or text |
| `browser_console_messages` | Read JS console output |
| `browser_network_requests` | List network requests |
| `browser_take_screenshot` | Capture a screenshot |
| `browser_tabs` | List / manage open tabs |
| `browser_lock` / `browser_unlock` | Lock tab before interactions, unlock when done |

**Flutter web note:** Flutter renders into a `<flutter-view>` element. The DOM accessibility tree is minimal until you click the `flutter-view` container (`e1` ref) to enable accessibility. After that, form fields appear as `role: textbox` refs.

---

### 2. `project-0-garbanzo_ai-dart-mcp-server` — Dart/Flutter tooling

Talks to the running Flutter app and the Dart SDK. Most tools require `connect_dart_tooling_daemon` to be called first with the DTD URI returned by `launch_app`.

| Tool | Purpose |
|------|---------|
| `list_devices` | List available Flutter devices (chrome, edge, windows, …) |
| `launch_app` | Start the Flutter app; returns `dtdUri` + `pid` |
| `list_running_apps` | List PIDs + DTD URIs of all running Flutter apps |
| `stop_app` | Stop a running app by PID |
| `connect_dart_tooling_daemon` | Connect to DTD — required before widget/log tools |
| `get_widget_tree` | Inspect the live widget tree (needs DTD connection) |
| `get_app_logs` | Stream app log output |
| `get_runtime_errors` | Get Dart runtime errors |
| `hot_reload` | Trigger a hot reload |
| `hot_restart` | Trigger a hot restart |
| `flutter_driver` | Interact with widgets: `tap`, `enter_text`, `get_text`, `waitFor`, `scroll`, … |
| `run_tests` | Run Dart/Flutter tests |
| `analyze_files` | Run `dart analyze` on files |
| `dart_fix` | Apply automated fixes |
| `dart_format` | Format Dart files |
| `pub` | Run `flutter pub` / `dart pub` commands |
| `pub_dev_search` | Search pub.dev for packages |

**Important:** `launch_app` opens a **separate browser window** that the `cursor-ide-browser` MCP cannot see. For E2E tests that combine both MCPs, start Flutter with `just fe-run-test-server` in a terminal instead, then navigate with `browser_navigate`.

---

### 3. `project-0-garbanzo_ai-chrome-devtools` — Chrome DevTools Protocol

Low-level Chrome DevTools access. Use when you need JavaScript evaluation, performance profiling, or control over a Chrome tab that is **not** the Cursor built-in browser.

| Tool | Purpose |
|------|---------|
| `list_pages` | List open Chrome pages |
| `select_page` | Switch active page |
| `new_page` | Open a new tab |
| `navigate_page` | Navigate a page to a URL |
| `evaluate_script` | Execute JavaScript in the page |
| `click` / `fill` / `fill_form` / `hover` / `drag` | Interact with page elements |
| `press_key` | Send a key event |
| `take_screenshot` / `take_snapshot` | Capture visual state |
| `list_network_requests` / `get_network_request` | Inspect network traffic |
| `list_console_messages` / `get_console_message` | Read console output |
| `performance_start_trace` / `performance_stop_trace` / `performance_analyze_insight` | CPU/performance profiling |
| `emulate` | Emulate device / network conditions |
| `close_page` | Close a tab |

---

## Typical E2E Workflow

```
1. just be-dev                          # terminal 1 – start backend
2. just fe-run-test-server              # terminal 2 – Flutter on port 8080
3. browser_navigate → http://localhost:8080
4. browser_snapshot                     # confirm page loaded
5. browser_click e1 (flutter-view)      # enable accessibility
6. browser_snapshot                     # now textbox refs are visible
7. browser_fill / browser_press_key     # interact with the form
8. browser_press_key Enter              # submit
9. Read backend terminal file           # verify API request + status code
```

For widget-level inspection add:
```
list_running_apps → note dtdUri
connect_dart_tooling_daemon(dtdUri)
get_widget_tree / get_app_logs / flutter_driver
```
