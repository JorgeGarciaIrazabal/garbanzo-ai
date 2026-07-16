import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/auth_state.dart';
import 'package:garbanzo_ai/core/router.dart';
import 'package:garbanzo_ai/core/theme.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/knowledge_base/providers/knowledge_base_provider.dart';
import 'package:garbanzo_ai/features/memory/providers/memory_provider.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';
import 'package:garbanzo_ai/features/notifications/services/push_service.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  // Clean path URLs on web (no /#/). The backend's SPA catch-all serves
  // index.html for unknown paths, so deep links survive a refresh.
  usePathUrlStrategy();
  // Kick off the initial token load before the first widget builds so
  // auth-bearing requests from providers see an in-memory token immediately.
  unawaited(ApiClient.instance.loadToken());
  unawaited(PushService.instance.init());
  runApp(const GarbanzoApp());
}

class GarbanzoApp extends StatefulWidget {
  const GarbanzoApp({super.key});

  @override
  State<GarbanzoApp> createState() => _GarbanzoAppState();
}

class _GarbanzoAppState extends State<GarbanzoApp> {
  final AuthState _authState = AuthState();
  late final GoRouter _router = buildRouter(_authState);
  StreamSubscription<String>? _pushRoomSub;

  @override
  void initState() {
    super.initState();
    // Listen for room deep-links from push notification taps.
    _pushRoomSub = PushService.instance.onOpenRoom.listen((roomId) {
      if (_authState.loggedIn) {
        _router.go('/rooms/$roomId');
      }
    });
    // Allow AuthState to defer-navigate after a manual login.
    _authState.pendingRoomNavigator = (roomId) {
      _router.go('/rooms/$roomId');
    };
    // After the initial auth check completes, navigate to a pending room.
    _authState.ensureReady().then((_) {
      final pending = PushService.instance.pendingRoomId;
      if (pending != null && _authState.loggedIn) {
        PushService.instance.pendingRoomId = null;
        _router.go('/rooms/$pending');
      }
    });
  }

  @override
  void dispose() {
    _pushRoomSub?.cancel();
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
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp.router(
            title: 'Garbanzo AI',
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: settings.loaded
                ? settings.flutterThemeMode
                : ThemeMode.system,
            routerConfig: _router,
            builder: (context, child) => _AppProviders(child: child!),
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
        ChangeNotifierProvider(create: (_) => SystemPromptProvider()),
        ChangeNotifierProvider(create: (_) => ToolProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => KnowledgeBaseProvider()),
        ChangeNotifierProvider(create: (_) => RoomProvider()),
      ],
      child: child,
    );
  }
}
