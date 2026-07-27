# Frontend — Agent Context

Flutter client (web/desktop/Android) with Provider state management and Freezed
data classes. This file is the package-local quick reference. Detailed
reference is read on demand: `../docs/architecture.md` (frontend layout,
provider map, chat/SSE flow, rooms WebSocket) and `../docs/api.md` (endpoints).

## Commands (always via `just`, never `flutter`/`dart` directly)

- `just fe-run` — Linux desktop (default); `just fe-run-chrome` — web
- `just fe-build-apk` — compile a debug Android APK without launching it
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
- Config in `l10n.yaml`. Run `just fe-gen-l10n` after editing ARB files and
  **commit** the generated files. `just fe-lint` runs generation first so stale
  localization output cannot make analysis misleading.
- Usage: `AppLocalizations.of(context)!.language`. Supported locales: en, es.
- Locale override: `SettingsProvider.appLocale` (enum `AppLocale` =
  system/english/spanish) persisted to SharedPreferences, mapped to
  `MaterialApp.locale` via `flutterLocale`. Language picker is in Settings →
  Appearance.
- When adding a user-facing string, add the key to `app_en.arb` (with a `@key`
  description) and its Spanish translation to `app_es.arb`.
- Reuse existing keys for common labels (`cancel`, `save`, `delete`, `create`,
  etc.) instead of duplicating entries.
- Keep provider/service error strings in English; localize them at the widget
  layer where `BuildContext` is available.

## Gotchas

- Web integration tests (`-d chrome`) are unsupported — use `-d linux` for E2E.
- API base URL: `--dart-define=API_BASE_URL` > debug `localhost:8000` > web-release
  relative origin.
- `MarkdownWidget` already gets tables, task lists, and strikethrough from
  `ExtensionSet.gitHubWeb`. Do not register those syntaxes again: duplicate
  table parsers crash on temporarily incomplete tables during SSE streaming.

- Micro-app panel on Android: the WebView loads a plain-HTTP dev-server URL in
  dev (port 8100–8500). Android 9+ blocks cleartext by default, so debug builds
  set `android:usesCleartextTraffic="true"` in `android/app/src/debug/AndroidManifest.xml`;
  release builds stay strict (prod serves the panel over HTTPS via the
  `/micro-apps` reverse proxy on the API origin). `MicroAppView`'s native
  branch wires a `NavigationDelegate` (`onHttpError`/`onWebResourceError`) so a
  blocked/failed load surfaces a retry card instead of a blank panel — keep
  that wiring when touching the WebView.
- Micro-app panel platform routing (`micro_app_view_native.dart`): Android/iOS
  → `webview_flutter`; Windows → `flutter_inappwebview` (WebView2) for an
  inline panel (the only desktop OS we ship to); Linux/macOS → "open in
  browser" card with an `url_launcher` Open button and a copy fallback, since
  no stable inline-webview plugin targets those platforms. Both the Android
  and Windows paths share the same load-state model (`onHttpError`/`onReceivedError`
  → retry card) — keep them in sync when changing the failure UI.
