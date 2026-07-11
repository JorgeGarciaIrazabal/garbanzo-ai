import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/core/widgets/auth_form_layout.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLoginSuccess,
  });

  final VoidCallback onLoginSuccess;

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

    try {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeFailure(
          e,
          unauthorizedMessage: 'Incorrect email or password',
        );
      });
    }
  }

  String get _backendLabel {
    final url = ApiClient.instance.baseUrl;
    return url.isEmpty ? 'relative (same host)' : url;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AuthFormLayout(
      icon: Icons.account_circle,
      heading: 'Sign in',
      formKey: _formKey,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_outlined, size: 13, color: colorScheme.outline),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _backendLabel,
                    style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('email_field'),
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
        PasswordField(
          key: const ValueKey('password_field'),
          controller: _passwordController,
          onSubmit: _submit,
        ),
        if (_error != null) AuthErrorBanner(message: _error!),
        const SizedBox(height: 24),
        AuthSubmitButton(
          key: const ValueKey('login_button'),
          label: 'Sign in',
          isLoading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
