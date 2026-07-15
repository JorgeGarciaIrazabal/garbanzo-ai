import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/user_avatar.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:garbanzo_ai/features/settings/widgets/change_password_dialog.dart';
import 'package:garbanzo_ai/features/settings/widgets/edit_profile_dialog.dart';

/// Profile block: shows account identity and exposes edit / password dialogs.
///
/// The settings page owns refresh; callers pass [onUserChanged] so the page
/// can re-read `AuthService.cachedUser` after a successful edit.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.user,
    required this.onUserChanged,
    required this.onLogout,
  });

  final UserInfo? user;
  final VoidCallback onUserChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = (user?.fullName?.isNotEmpty ?? false)
        ? user!.fullName!
        : (user?.email ?? 'Unknown user');

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: () => _showAvatarOptions(context),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    profilePictureB64: user?.profilePictureB64,
                    displayName: displayName,
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: colorScheme.surface, width: 1.5),
                        ),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 12,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            title: Text(displayName, style: theme.textTheme.titleMedium),
            subtitle: Text(user?.email ?? ''),
            trailing: user?.isAdmin ?? false
                ? Chip(
                    label: const Text('Admin'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: colorScheme.primaryContainer,
                    side: BorderSide.none,
                  )
                : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit profile'),
            subtitle: const Text('Update name and email'),
            onTap: () async {
              final changed = await showAnimatedDialog<bool>(
                context: context,
                builder: (_) => EditProfileDialog(user: user),
              );
              if (changed == true) onUserChanged();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            onTap: () async {
              await showAnimatedDialog<void>(
                context: context,
                builder: (_) => const ChangePasswordDialog(),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: colorScheme.error)),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }

  void _showAvatarOptions(BuildContext context) {
    final hasAvatar =
        user?.profilePictureB64 != null && user!.profilePictureB64!.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose photo'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickImage(context, fromCamera: false);
                },
              ),
              if (FilePickerHelper.isMobilePlatform)
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take photo'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(context, fromCamera: true);
                  },
                ),
              if (hasAvatar)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Remove photo',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _removeAvatar(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(
    BuildContext context, {
    required bool fromCamera,
  }) async {
    Uint8List? bytes;
    String? filename;

    if (fromCamera && FilePickerHelper.isMobilePlatform) {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (photo == null) return;
      bytes = await photo.readAsBytes();
      filename = photo.name;
    } else {
      final isMobile = FilePickerHelper.isMobilePlatform;
      if (isMobile) {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (photo == null) return;
        bytes = await photo.readAsBytes();
        filename = photo.name;
      } else {
        final result = await FilePicker.pickFiles(
          allowMultiple: false,
          withData: true,
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        if (file.bytes == null) return;
        bytes = file.bytes!;
        filename = file.name;
      }
    }

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    final updated = await AuthService.instance.uploadAvatar(bytes, filename);
    if (updated != null) {
      onUserChanged();
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile picture updated')),
        );
      }
    } else {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to upload profile picture')),
        );
      }
    }
  }

  Future<void> _removeAvatar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = await AuthService.instance.deleteAvatar();
    if (updated != null) {
      onUserChanged();
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile picture removed')),
        );
      }
    } else {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to remove profile picture')),
        );
      }
    }
  }
}
