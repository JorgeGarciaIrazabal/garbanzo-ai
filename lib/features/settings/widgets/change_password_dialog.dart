import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _obscureCurrent = true;
  bool _obscureNext = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await AuthService.instance.changePassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _saving = false;
        _error =
            result.error ??
            AppLocalizations.of(context)!.messageFailedToChangePassword;
      });
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.messagePasswordUpdated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.titleChangePassword),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _current,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelCurrentPassword,
                  suffixIcon: IconButton(
                    tooltip: _obscureCurrent
                        ? AppLocalizations.of(context)!.showPassword
                        : AppLocalizations.of(context)!.hidePassword,
                    icon: Icon(
                      _obscureCurrent ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? AppLocalizations.of(context)!.validationErrorRequired
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _next,
                obscureText: _obscureNext,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelNewPassword,
                  suffixIcon: IconButton(
                    tooltip: _obscureNext
                        ? AppLocalizations.of(context)!.showPassword
                        : AppLocalizations.of(context)!.hidePassword,
                    icon: Icon(
                      _obscureNext ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscureNext = !_obscureNext),
                  ),
                  helperText: AppLocalizations.of(
                    context,
                  )!.hintAtLeast6Characters,
                ),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return AppLocalizations.of(
                      context,
                    )!.validatorPasswordMinLength('6');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirm,
                obscureText: _obscureNext,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  )!.labelConfirmNewPassword,
                ),
                validator: (v) {
                  if (v != _next.text) {
                    return AppLocalizations.of(
                      context,
                    )!.messagePasswordsDoNotMatch;
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(AppLocalizations.of(context)!.change),
        ),
      ],
    );
  }
}
