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

## i18n

- Official Flutter l10n: `flutter_localizations` + gen-l10n. ARB sources live in
  `lib/l10n/app_en.arb` (template) and `app_es.arb`; output is generated to
  `lib/l10n/gen/` (import `package:garbanzo_ai/l10n/gen/app_localizations.dart`).
- Config in `l10n.yaml`. `pubspec.yaml` has `flutter: generate: true`, so gen-l10n
  runs automatically on build/analyze. Run `flutter gen-l10n` manually after
  editing ARB files and **commit** the generated files.
- Usage: `AppLocalizations.of(context)!.language`. Supported locales: en, es.
- Locale override: `SettingsProvider.appLocale` (enum `AppLocale` =
  system/english/spanish) persisted to SharedPreferences, mapped to
  `MaterialApp.locale` via `flutterLocale`. Language picker is in Settings →
  Appearance.
- When adding a user-facing string, add the key to `app_en.arb` (with a `@key`
  description) and its Spanish translation to `app_es.arb`.

## Gotchas

- Web integration tests (`-d chrome`) are unsupported — use `-d linux` for E2E.
- API base URL: `--dart-define=API_BASE_URL` > debug `localhost:8000` > web-release
  relative origin.
