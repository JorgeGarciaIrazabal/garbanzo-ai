import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/error_reporter.dart';
import 'package:garbanzo_ai/core/auth_state.dart';
import 'package:garbanzo_ai/core/router.dart';
import 'package:garbanzo_ai/core/theme.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/features/chat/services/shared_content_service.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';
import 'package:garbanzo_ai/features/knowledge_base/providers/knowledge_base_provider.dart';
import 'package:garbanzo_ai/features/memory/providers/memory_provider.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';
import 'package:garbanzo_ai/features/notifications/services/push_service.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/update_banner.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';

void main() => runZonedGuarded(
  () {
    if (kDebugMode) {
      MarionetteBinding.ensureInitialized();
    } else {
      WidgetsFlutterBinding.ensureInitialized();
    }
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        ErrorReporter.instance.report(
          details.exception,
          details.stack ?? StackTrace.current,
        ),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(ErrorReporter.instance.report(error, stack));
      return true;
    };
    // Clean path URLs on web (no /#/). The backend's SPA catch-all serves
    // index.html for unknown paths, so deep links survive a refresh.
    usePathUrlStrategy();
    // Kick off the initial token load before the first widget builds so
    // auth-bearing requests from providers see an in-memory token immediately.
    unawaited(ApiClient.instance.loadToken());
    unawaited(PushService.instance.init());
    runApp(const GarbanzoApp());
  },
  (error, stack) {
    unawaited(ErrorReporter.instance.report(error, stack));
  },
);

class GarbanzoApp extends StatefulWidget {
  const GarbanzoApp({super.key});

  @override
  State<GarbanzoApp> createState() => _GarbanzoAppState();
}

class _GarbanzoAppState extends State<GarbanzoApp> {
  final AuthState _authState = AuthState();
  late final GoRouter _router = buildRouter(_authState);
  StreamSubscription<String>? _pushRouteSub;
  StreamSubscription<SharedContent>? _sharedContentSub;

  @override
  void initState() {
    super.initState();
    // Listen for deep-links from push notification taps (rooms or
    // conversations — see PushService.routeForData).
    _pushRouteSub = PushService.instance.onOpenRoute.listen((route) {
      if (_authState.loggedIn) {
        // Consume it — otherwise a later logout→login would replay this
        // route via AuthState's pending-route check. When logged out it
        // stays set on purpose: that's the deferred-navigation case.
        PushService.instance.pendingRoute = null;
        _router.go(route);
      }
    });
    // A share intent may arrive on a cold start or while another page is
    // visible. Keep the content queued and bring the regular chat composer
    // forward; it stages the files/text so the user can review before sending.
    _sharedContentSub = SharedContentService.instance.incoming.listen((_) {
      final path = _router.routeInformationProvider.value.uri.path;
      if (!path.startsWith('/chat')) _router.go('/chat');
    });
    unawaited(SharedContentService.instance.start());
    // Allow AuthState to defer-navigate after a manual login.
    _authState.pendingRouteNavigator = (route) {
      _router.go(route);
    };
    // After the initial auth check completes, navigate to a pending route.
    _authState.ensureReady().then((_) {
      final pending = PushService.instance.pendingRoute;
      if (pending != null && _authState.loggedIn) {
        PushService.instance.pendingRoute = null;
        _router.go(pending);
      }
    });
  }

  @override
  void dispose() {
    _pushRouteSub?.cancel();
    _sharedContentSub?.cancel();
    _router.dispose();
    _authState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authState),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        // Native auto-update: silent check at startup (no-op where unsupported).
        ChangeNotifierProvider(create: (_) => UpdateProvider()..silentCheck()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp.router(
            onGenerateTitle: (context) =>
                AppLocalizations.of(context)!.appTitle,
            locale: settings.flutterLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: settings.loaded
                ? settings.flutterThemeMode
                : ThemeMode.system,
            routerConfig: _router,
            builder: (context, child) =>
                _AppProviders(child: UpdateBanner(child: child!)),
          );
        },
      ),
    );
  }
}

/// User-scoped providers, mounted above the navigator so every route shares
/// one instance (pushed pages no longer re-create their own copies).
///
/// All providers are lazy — nothing is constructed while on /login. The
/// subtree is keyed on [AuthState.epoch], which increments on logout, so a
/// new login starts from disposed-and-rebuilt provider state.
class _AppProviders extends StatelessWidget {
  const _AppProviders({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final epoch = context.select<AuthState, int>((a) => a.epoch);
    return MultiProvider(
      key: ValueKey(epoch),
      providers: [
        ChangeNotifierProvider(create: (_) => ModelProvider()),
        ChangeNotifierProvider(create: (_) => StyleProvider()),
        // Model selection and the style picker's pending thinking/prompt
        // live outside ChatProvider so they survive conversation switches;
        // the proxy pushes the latest values in for new-conversation creates.
        ChangeNotifierProxyProvider2<
          ModelProvider,
          StyleProvider,
          ChatProvider
        >(
          create: (_) => ChatProvider(),
          update: (_, model, style, chat) => chat!
            ..selectedModelId = model.selectedModelId
            ..pendingThinkingLevel = style.pendingThinkingLevel
            ..pendingSystemPrompt = style.pendingSystemPrompt,
        ),
        ChangeNotifierProvider(create: (_) => MemoryProvider()),
        // Above the message list on purpose: a delegated workflow runs for
        // minutes, long after its tile has scrolled out of view. The proxy
        // wires completion back into the chat so the run's summary message
        // (written server-side) actually shows up without a manual reload.
        ChangeNotifierProxyProvider<ChatProvider, WorkflowProvider>(
          // WorkflowProvider needs the per-conversation folder path (and the
          // current conversation id) to auto-apply a finished run's diff to
          // the user's disk — without this it would have no way to resolve
          // the folder outside a BuildContext, and a card mid-deactivation
          // (a ListView.builder reparents on scroll) would crash.
          create: (context) =>
              WorkflowProvider(chat: context.read<ChatProvider>()),
          update: (context, chat, workflows) =>
              workflows!
                ..onRunFinished = (conversationId) {
                  if (chat.currentConversation?.id == conversationId) {
                    unawaited(chat.loadConversation(conversationId));
                  }
                },
        ),
        ChangeNotifierProvider(create: (_) => SystemPromptProvider()),
        ChangeNotifierProvider(create: (_) => ToolProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => KnowledgeBaseProvider()),
        ChangeNotifierProvider(create: (_) => RoomProvider()),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
      ],
      child: child,
    );
  }
}
