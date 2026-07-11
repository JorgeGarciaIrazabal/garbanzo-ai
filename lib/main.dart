import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/theme.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_page.dart';
import 'package:garbanzo_ai/features/notifications/services/push_service.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/pages/login_page.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  // Kick off the initial token load before the first widget builds so
  // auth-bearing requests from providers see an in-memory token immediately.
  unawaited(ApiClient.instance.loadToken());
  unawaited(PushService.instance.init());
  runApp(const GarbanzoApp());
}

class GarbanzoApp extends StatelessWidget {
  const GarbanzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'Garbanzo AI',
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: settings.loaded
                ? settings.flutterThemeMode
                : ThemeMode.system,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final isLoggedIn = await AuthService.instance.isLoggedIn();
    if (mounted) {
      setState(() {
        _loggedIn = isLoggedIn;
        _checking = false;
      });
    }
    if (isLoggedIn) {
      unawaited(PushService.instance.registerDevice());
    }
  }

  void _onLoginSuccess() {
    setState(() => _loggedIn = true);
    // Fire-and-forget: populate cached user (including is_admin) without
    // blocking the UI transition.
    unawaited(AuthService.instance.getCurrentUser());
    unawaited(PushService.instance.registerDevice());
  }

  void _onLogout() {
    setState(() => _loggedIn = false);
    unawaited(PushService.instance.unregisterDevice());
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loggedIn) {
      return ChatPage(onLogout: _onLogout);
    }

    return LoginPage(onLoginSuccess: _onLoginSuccess);
  }
}
