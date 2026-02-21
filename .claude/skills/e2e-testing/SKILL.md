---
name: e2e-testing
description: E2E testing workflow for the Flutter app using MCP tools
---

# E2E Testing with MCPs

## Starting the Stack

Always start services in this order:

1. **Backend** (FastAPI on port 8000):
   ```powershell
   just be-dev
   # or: cd backend; uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

2. **Flutter frontend** (web-server on fixed port 8080):
   ```powershell
   just fe-run-test-server
   # or: flutter run -d web-server --web-port=8080 --web-hostname=localhost
   ```

   Do NOT use `just fe-run` / `flutter run -d chrome` for testing - it launches a new Chrome window on a random port that the browser MCP cannot access.

3. **Verify both are up** by checking terminal output before proceeding.

## Launching via Dart MCP (Alternative)

The dart-mcp-server `launch_app` tool is available but opens a **separate browser window** the browser MCP cannot see. Only use it when widget-tree inspection via `get_widget_tree` / `flutter_driver` is needed.

```
list_devices        → pick "edge" or "chrome"
launch_app          → returns DTD URI + PID
connect_dart_tooling_daemon(uri)
get_widget_tree / get_app_logs / get_runtime_errors
```

## Browser MCP Interaction Pattern

After navigating to `http://localhost:8080`:

1. Flutter renders inside a `<flutter-view>` — the full widget tree is NOT in the DOM.
2. Accessibility must be enabled first — click the `flutter-view` container (`e1` ref) once to reveal form fields as `role: textbox`.
3. Then use `browser_fill` (not `browser_type`) to set field values reliably.
4. Use `browser_press_key` with `"Tab"` to move between fields.
5. Use `browser_press_key` with `"Enter"` or click the submit button ref to submit.
6. Use `browser_snapshot` after every action to see the updated accessible tree.
7. Use `browser_console_messages` to check for JS errors or network failures.

### Checking API traffic

After form submission, read the **backend terminal file** to confirm the HTTP request was made and check the status code. This is the most reliable verification method.

## Stopping Processes

```powershell
# Stop all Flutter/Dart processes
taskkill /F /FI "IMAGENAME eq dart.exe"

# Stop backend (Python/uvicorn)
taskkill /F /FI "IMAGENAME eq python.exe"
```

Or use the dart-mcp `stop_app` tool with the PID from `list_running_apps`.

## Integration Tests (flutter test)

`flutter test integration_test/ -d chrome` **does not work** — Flutter web is not yet supported for integration tests.

Use `-d windows` (Windows desktop) for integration test runs:
```powershell
flutter test integration_test/app_test.dart -d windows
```

Integration tests live in `integration_test/` and require the `integration_test` SDK package (already in `pubspec.yaml`).

## Key URLs

| Service | URL |
|---------|-----|
| Backend API | http://localhost:8000 |
| Flutter (test server) | http://localhost:8080 |
| Flutter (backend-served prod build) | http://localhost:8000 |

## API base URL

In debug mode the Flutter app always calls `http://localhost:8000` (hardcoded in `lib/core/api_client.dart`). Override with `--dart-define=API_BASE_URL=https://...` for other environments.
