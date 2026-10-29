# Frontend — Agent Context

Flutter client (web/desktop/Android) with `Provider` (`ChangeNotifier`) state
management, `GoRouter` navigation, and `Freezed` / `@immutable` models. Detailed
reference lives in `../docs/architecture.md` and `../docs/api.md`. Feature-deep
invariants live in `features/chat/AGENTS.md` and `features/rooms/AGENTS.md`.

## Commands (always via `just`, never `flutter`/`dart` directly)

- `just fe-run` — Linux desktop (default); `just fe-run-chrome` — web
- `just fe-build-apk` / `just fe-build-apk-release` — debug / signed release APK
- `just fe-test` — full unit/widget suite (`--concurrency=4`)
- `just fe-test test/path/foo_test.dart --plain-name "multi word name"` — focused test
- `just fe-lint` — `gen-l10n` + `flutter analyze` across `lib/` and `test/`
- `just fe-lint-arch` — ARB parity, UI import boundaries, and 800-line file ceiling
- `just fe-format` / `just fe-format-check` — format or check `lib/` + `test/`

## Where code goes

- `features/<feature>/` split into `models/`, `services/`, `providers/`,
  `widgets/`, `pages/`. Keep non-UI layers (`models/`, `services/`, `providers/`)
  free of `widgets/` and `pages/` imports (enforced by `just fe-lint-arch`).
- `core/` — cross-feature infrastructure: `router.dart` (`GoRouter`),
  `api_client.dart` (Dio + base-URL + JWT), `api_error.dart` (status/detail
  helpers), `guarded_state.dart` (`GuardedStateMixin`),
  `throttled_message_notifier.dart` (80ms stream coalescing), `auth_state.dart`,
  `responsive.dart`, and `core/widgets/` for shared UI primitives.
- Keep non-generated `lib/**/*.dart` files ≤ 800 lines; split growing widgets or
  controllers into focused files before hitting the `just fe-lint-arch` ceiling.

## Conventions

- **Navigation & Auth Epoch:** `lib/main.dart` mounts `MaterialApp.router` with
  `createAppRouter()` (`lib/core/router.dart`, refreshed by `AuthState`) inside
  `_AppProviders(key: ValueKey(epoch))`. Logging out or switching accounts bumps
  `AuthState.epoch`, disposing and recreating every user-scoped `ChangeNotifier`
  automatically — never add manual per-provider logout reset wiring.
- **HTTP & Error Contract (`validateStatus: (_) => true`):** `ApiClient` never
  throws `DioException` on 4xx/5xx responses — only on transport/timeout errors.
  - Every HTTP service MUST accept `{ApiClient? api}` (`: _api = api ?? ApiClient.instance`)
    so unit tests inject a `mocktail` `Mock` without touching `SharedPreferences`.
  - Always check status codes explicitly via `expectStatus(...)` or throw
    `apiResponseError(...)` (`lib/core/api_error.dart`). Never write
    `response.data['detail'] as String?` — FastAPI 422 responses return a `List`
    of validation maps, which `apiErrorDetail` extracts safely.
- **Providers & Disposal Safety:** Mix in `GuardedStateMixin` (`runGuarded`,
  `setError`, `clearError`, `isLoading`, `error`), which maps `ApiResponseException`
  and `DioException` to clean English messages and suppresses `notifyListeners()`
  after `dispose()`. Custom async providers without `GuardedStateMixin` must guard
  post-`await` notifications with a `_disposed` flag.
- **Optional Ancestor Providers:** When a widget can render outside the full app
  shell (e.g., isolated widget tests or sheets), read optional providers with
  `context.read<T?>()` or `context.watch<T?>()`. Never wrap `context.read<T>()`
  in `try { ... } catch (_) {}`.
- **No Silent Catches:** `empty_catches`, `cancel_subscriptions`, and
  `close_sinks` are enabled in `analysis_options.yaml`. Log and surface runtime
  failures; if a cleanup-only `catch` is genuinely best-effort (e.g. deleting a
  temp file), document why in a comment.
- **Models:** Use `@freezed` + `json_serializable` when `copyWith`, structural
  equality, or sealed unions are needed (`just fe-gen-models` and commit
  `.freezed.dart`/`.g.dart`). Simple immutable wire DTOs may use `@immutable`
  with manual `fromJson`.
- **Settings UX:** `SettingsPage` (`/settings`) is the single full settings page;
  `SettingsDrawer` is a compact quick menu (`This conversation`, `Pages`, 1-tap
  theme toggle, and `"Open full settings"`). Shared voice controls live in
  `VoiceSettingsTiles` (`features/settings/widgets/voice_settings_tiles.dart`).
- **Testing:** Use `pumpLocalizedApp` / `buildLocalizedTestApp`
  (`test/helpers/pump_app.dart`), `mocktail` for `ApiClient`/services, and
  `fakeAsync` for timers.

## i18n

- ARB sources live in `lib/l10n/app_en.arb` (template) and `lib/l10n/app_es.arb`;
  generated output lives in `lib/l10n/gen/` (`just fe-gen-l10n`, committed).
- Add every new user-facing string to **both** `app_en.arb` and `app_es.arb` with
  identical `{placeholder}` names (`just fe-lint-arch` enforces key and ICU
  placeholder parity).
- Keep service/provider error strings in English and localize at the widget layer.

## Gotchas

- Web integration tests (`-d chrome`) are unsupported — use `-d linux` or Android for E2E.
- API base URL precedence: `--dart-define=API_BASE_URL` > debug `http://127.0.0.1:8000`
  > web-release relative origin.
- `MarkdownWidget` already gets tables, task lists, and strikethrough from
  `ExtensionSet.gitHubWeb`. Do not re-register those syntaxes: duplicate table
  parsers crash on incomplete tables during SSE streaming.
- Generated `render_ui` results are answer content: keep them outside
  `ChatTranscriptView`'s collapsible tool-activity groups, like proposal cards.
  The shared catalog in `backend/app/schemas/visual_ui_catalog.json` is bundled
  as a Flutter asset — update validation and rendering together. GenUI error
  messages expose `DataPart` values via `uiInteractionParts`; catalog widget
  tests must evict the cached `rootBundle` future between runs.
- Micro-app panel routing (`micro_app_view_native.dart`): Android/iOS →
  `webview_flutter` (debug manifest enables cleartext HTTP for dev ports
  8100–8500; release uses HTTPS `/micro-apps`); Windows → `flutter_inappwebview`
  (WebView2); Linux/macOS → `url_launcher` browser card. Keep `onHttpError` /
  `onReceivedError` retry-card handling in sync across Android and Windows.
- `AlertDialog` measures intrinsic dimensions even with `scrollable: true`: give
  embedded lazy lists (`ListView.builder` / `ExpansionTile` children) a bounded
  height (`SizedBox`), or layout throws.
