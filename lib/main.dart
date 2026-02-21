import 'package:flutter/material.dart';

import 'core/auth_service.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';

void main() {
  runApp(const GarbanzoApp());
}

class GarbanzoApp extends StatelessWidget {
  const GarbanzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garbanzo AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthGate(),
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
  }

  void _onLoginSuccess() {
    setState(() => _loggedIn = true);
  }

  void _onRegisterSuccess() {
    setState(() => _loggedIn = true);
  }

  void _onLogout() {
    setState(() => _loggedIn = false);
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
      return HomePage(onLogout: _onLogout);
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
