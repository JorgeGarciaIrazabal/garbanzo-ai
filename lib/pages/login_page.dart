import 'package:flutter/material.dart';

import '../core/auth_service.dart';
import '../core/widgets/auth_form_layout.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLoginSuccess,
    this.onNavigateToRegister,
  });

  final VoidCallback onLoginSuccess;
  final VoidCallback? onNavigateToRegister;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _error = null;
      _loading = true;
    });

    final result = await AuthService.instance.login(
      _emailController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      widget.onLoginSuccess();
    } else {
      setState(() => _error = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      icon: Icons.account_circle,
      heading: 'Sign in',
      formKey: _formKey,
      children: [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Enter your email';
            if (!v.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outlined),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your password';
            return null;
          },
        ),
        if (_error != null) AuthErrorBanner(message: _error!),
        const SizedBox(height: 24),
        AuthSubmitButton(
          label: 'Sign in',
          isLoading: _loading,
          onPressed: _submit,
        ),
        if (widget.onNavigateToRegister != null) ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loading ? null : widget.onNavigateToRegister,
            child: const Text('Create an account'),
          ),
        ],
      ],
    );
  }
}
