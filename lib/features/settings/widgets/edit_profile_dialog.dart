import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Edits full name and email. On successful email change, signs the user out —
/// the old JWT is bound to the previous email.
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({super.key, required this.user});

  final UserInfo? user;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user?.fullName ?? '');
    _email = TextEditingController(text: widget.user?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final originalEmail = widget.user?.email ?? '';
    final newEmail = _email.text.trim();
    final emailChanged = newEmail.toLowerCase() != originalEmail.toLowerCase();

    final newName = _name.text.trim();
    final nameChanged = newName != (widget.user?.fullName ?? '');

    final result = await AuthService.instance.updateProfile(
      fullName: nameChanged ? newName : null,
      email: emailChanged ? newEmail : null,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _saving = false;
        _error =
            result.error ??
            AppLocalizations.of(context)!.messageFailedToUpdateProfile;
      });
      return;
    }

    if (emailChanged) {
      // The old JWT is now invalid; force the user to log back in.
      await AuthService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.messageEmailUpdatedSignInAgain,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.titleEditProfile),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelFullName,
                  prefixIcon: Icon(Icons.person_outline),
                ),
                maxLength: 100,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.labelEmail,
                  prefixIcon: Icon(Icons.email_outlined),
                  helperText: AppLocalizations.of(
                    context,
                  )!.messageChangingEmailSignsYouOut,
                ),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) {
                    return AppLocalizations.of(context)!.messageEmailRequired;
                  }
                  if (!v.contains('@')) {
                    return AppLocalizations.of(
                      context,
                    )!.validatorEnterValidEmail;
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
              : Text(AppLocalizations.of(context)!.save),
        ),
      ],
    );
  }
}
