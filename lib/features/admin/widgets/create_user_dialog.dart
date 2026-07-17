import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Result returned from [CreateUserDialog].
class CreateUserDialogResult {
  final String email;
  final String password;
  final String? fullName;
  final bool isAdmin;

  const CreateUserDialogResult({
    required this.email,
    required this.password,
    this.fullName,
    required this.isAdmin,
  });
}

/// Dialog for creating a new user (admin only).
class CreateUserDialog extends StatefulWidget {
  const CreateUserDialog({super.key});

  static Future<CreateUserDialogResult?> show(BuildContext context) {
    return showAnimatedDialog<CreateUserDialogResult>(
      context: context,
      builder: (_) => const CreateUserDialog(),
    );
  }

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  bool _isAdmin = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final result = CreateUserDialogResult(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _fullNameController.text.trim().isEmpty
          ? null
          : _fullNameController.text.trim(),
      isAdmin: _isAdmin,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.titleCreateUser),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('full_name_field'),
                controller: _fullNameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  )!.labelFullNameOptional,
                  hintText: AppLocalizations.of(context)!.hintJaneDoe,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('email_field'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelEmail,
                  hintText: AppLocalizations.of(context)!.hintYouExampleCom,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter an email';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('password_field'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelPassword,
                  hintText: AppLocalizations.of(
                    context,
                  )!.hintAtLeast6Characters,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter a password';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
                title: Text(AppLocalizations.of(context)!.titleAdminPrivileges),
                subtitle: Text(
                  AppLocalizations.of(context)!.messageAllowAdminPrivileges,
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          key: const ValueKey('create_user_submit'),
          onPressed: _submit,
          child: Text(AppLocalizations.of(context)!.create),
        ),
      ],
    );
  }
}
