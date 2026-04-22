import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:provider/provider.dart';

import 'core/auth_service.dart';
import 'features/chat/widgets/chat_page.dart';
import 'features/notifications/services/push_service.dart';
import 'features/settings/providers/settings_provider.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  unawaited(PushService.instance.init());
  runApp(const GarbanzoApp());
}

class GarbanzoApp extends StatelessWidget {
  const GarbanzoApp({super.key});

  /// Light theme with a warm, professional color scheme.
  ThemeData get _lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4), // Deep purple
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Dark theme with proper contrast for readability.
  ThemeData get _darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4), // Deep purple
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'Garbanzo AI',
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: settings.loaded ? settings.flutterThemeMode : ThemeMode.system,
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
  bool _showRegister = false;

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

  void _onRegisterSuccess() {
    setState(() => _loggedIn = true);
    unawaited(AuthService.instance.getCurrentUser());
    unawaited(PushService.instance.registerDevice());
  }

  void _onLogout() {
    setState(() => _loggedIn = false);
    unawaited(PushService.instance.unregisterDevice());
  }

  void _showRegisterPage() {
    setState(() => _showRegister = true);
  }

  void _showLoginPage() {
    setState(() => _showRegister = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loggedIn) {
      return ChatPage(onLogout: _onLogout);
    }

    if (_showRegister) {
      return RegisterPage(
        onRegisterSuccess: _onRegisterSuccess,
        onNavigateToLogin: _showLoginPage,
      );
    }

    return LoginPage(
      onLoginSuccess: _onLoginSuccess,
      onNavigateToRegister: _showRegisterPage,
    );
  }
}
