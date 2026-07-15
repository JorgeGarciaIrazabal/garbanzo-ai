# Frontend — Agent Context

Flutter client (web/desktop/Android) with Provider state management and Freezed
data classes. This file is the package-local quick reference. Detailed
reference is read on demand: `../docs/architecture.md` (frontend layout,
provider map, chat/SSE flow, rooms WebSocket) and `../docs/api.md` (endpoints).

## Commands (always via `just`, never `flutter`/`dart` directly)

- `just fe-run` — Linux desktop (default); `just fe-run-chrome` — web
- `just fe-test` — unit/widget tests; `just fe-lint` / `just fe-format`
- Single test: `flutter test test/path/widget_test.dart`

## Where code goes

- `features/<feature>/` split into `models/`, `providers/`, `services/`,
  `widgets/`, `pages/`. Keep a feature self-contained.
- `core/` — cross-feature singletons: `api_client.dart` (dio + base-URL
  resolution + token), `auth_service.dart`, `responsive.dart`.

## Conventions

- State: `Provider`/`ChangeNotifier`. `ModelProvider` and `ChatProvider` are kept
  separate so model selection survives conversation switches.
- Models use `freezed` + `json_serializable`. After editing a `@freezed` file run
  `dart run build_runner build --delete-conflicting-outputs` and **commit** the
  generated `.freezed.dart` / `.g.dart`.
- JWT lives in `SharedPreferences` under `auth_token`; `ApiClient` reads it.

## Gotchas

- Web integration tests (`-d chrome`) are unsupported — use `-d linux` for E2E.
- API base URL: `--dart-define=API_BASE_URL` > debug `localhost:8000` > web-release
  relative origin.
