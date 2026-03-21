---
name: e2e-testing
description: E2E testing workflow for the Flutter app using MCP tools
---

# E2E Testing with Marionette + Dart MCP

## Workflow Overview

```
1. Start backend          → FastAPI on port 8000
2. Launch Flutter app     → via Dart MCP (launch_app) → get VM service URI
3. Connect Marionette     → connect(uri: <vm_service_uri>)
4. Interact + assert      → tap / enter_text / take_screenshots / get_logs
5. Inspect widget tree    → Dart MCP get_widget_tree / get_runtime_errors
6. Stop                   → Dart MCP stop_app
```

## Step 1 — Start the Backend

```bash
cd backend; uv run uvicorn app.main:app --reload --port 8000
# or: just be-dev
```

Verify it's up at `http://localhost:8000/health` before proceeding.

## Step 2 — Launch the Flutter App via Dart MCP

```
list_devices                     → pick "linux" (preferred) or "chrome"
launch_app(device_id: "linux")   → returns { dtd_uri, vm_service_uri, pid }
```

The `vm_service_uri` will look like `ws://127.0.0.1:PORT/ws`. Save it — you need it for Marionette.

> **Note:** `launch_app` on `linux` opens a native desktop window. On `chrome` it opens a browser. Either works for Marionette. Linux is preferred in WSL2 to avoid browser port randomness.

## Step 3 — Connect Marionette

```
connect(uri: "<vm_service_uri from launch_app>")
```

Marionette is now linked to the running Flutter app.

## Step 4 — Discover UI Elements

```
get_interactive_elements()
```

Elements are matched by `ValueKey<String>` (more reliable) or by text content. If an element is missing, add a `ValueKey` to it in the source code and hot_reload.

## Step 5 — Interact with the App

| Action | Tool | Notes |
|--------|------|-------|
| Tap a button / element | `tap(key: "submit_button")` or `tap(text: "Send")` | Keys preferred |
| Type into a field | `enter_text(key: "message_input", text: "Hello")` | Targets focused field |
| Scroll | `scroll_to(key: "message_list")` | Scrolls element into view |
| Screenshot | `take_screenshots()` | Check current UI state |
| Read logs | `get_logs()` | Debug print statements, errors |
| Hot reload after code change | `hot_reload()` | Preserves app state |

## Step 6 — Inspect with Dart MCP

```
connect_dart_tooling_daemon(uri: "<dtd_uri from launch_app>")
get_widget_tree()         → full widget hierarchy
get_runtime_errors()      → Dart/Flutter errors
get_app_logs()            → structured app output
```

Use `get_widget_tree` to find widget keys and verify rendering. Use `get_runtime_errors` after interactions to assert no crashes occurred.

## Step 7 — Stop the App

```
stop_app(pid: <pid from launch_app>)
# or: Dart MCP stop_app
```

## Running Unit/Integration Tests via Dart MCP

```
run_tests(path: "test/")                        → unit tests
run_tests(path: "integration_test/app_test.dart", device_id: "linux")
```

> Flutter web integration tests (`-d chrome`) are not supported. Use `linux` desktop device.

## Common Test Patterns

### Verify a chat message was sent

```
1. enter_text(key: "message_input", text: "Hello AI")
2. tap(key: "send_button")
3. take_screenshots()          → confirm message appears in list
4. get_logs()                  → confirm no errors
5. get_runtime_errors()        → assert empty
```

### Verify backend API call

After a user action, check the backend terminal output — HTTP request logs are the most reliable confirmation that the API was called.

### Adding keys to widgets

When `get_interactive_elements()` doesn't surface a widget, add a `ValueKey`:

```dart
TextField(key: const ValueKey('message_input'), ...)
ElevatedButton(key: const ValueKey('send_button'), ...)
```

Then `hot_reload()` via Marionette — no restart needed.

## Key References

| Service | Value |
|---------|-------|
| Backend API | `http://localhost:8000` |
| API base URL (debug) | `http://localhost:8000` (hardcoded in `lib/core/api_client.dart`) |
| Override API URL | `--dart-define=API_BASE_URL=https://...` |
