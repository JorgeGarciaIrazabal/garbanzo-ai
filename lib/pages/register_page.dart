import 'package:flutter/material.dart';

import '../core/auth_service.dart';
import '../core/widgets/auth_form_layout.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.onRegisterSuccess,
    required this.onNavigateToLogin,
  });

  final VoidCallback onRegisterSuccess;
  final VoidCallback onNavigateToLogin;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _error = null;
      _loading = true;
    });

    final result = await AuthService.instance.register(
      _emailController.text,
      _passwordController.text,
      fullName: _fullNameController.text.trim().isEmpty
          ? null
          : _fullNameController.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      widget.onRegisterSuccess();
    } else {
      setState(() => _error = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      icon: Icons.person_add,
      heading: 'Create account',
      formKey: _formKey,
      children: [
        TextFormField(
          controller: _fullNameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Full name (optional)',
            hintText: 'Jane Doe',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outlined),
          ),
        ),
        const SizedBox(height: 16),
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
            hintText: 'At least 6 characters',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outlined),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter a password';
            if (v.length < 6) return 'Password must be at least 6 characters';
            return null;
          },
        ),
        if (_error != null) AuthErrorBanner(message: _error!),
        const SizedBox(height: 24),
        AuthSubmitButton(
          label: 'Create account',
          isLoading: _loading,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loading ? null : widget.onNavigateToLogin,
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }
}
