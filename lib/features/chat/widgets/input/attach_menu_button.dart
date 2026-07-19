import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/platform_info.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Attach button for the message composer. Instead of jumping straight into
/// the file picker, it offers the available sources:
///   - Take photo (mobile only — opens the device camera)
///   - Photos (native photo picker on mobile, image-filtered file picker
///     on desktop/web)
///   - Files (the full file picker: documents, spreadsheets, images…)
///
/// Presented as a bottom sheet on narrow layouts and an anchored menu on
/// wide ones. Validation feedback (oversized files, duplicates) is shown via
/// snackbars here so callers only receive the attachments that passed.
class AttachMenuButton extends StatefulWidget {
  const AttachMenuButton({
    super.key,
    required this.enabled,
    required this.existingNames,
    required this.onAdded,
    this.onPickFolder,
    this.buttonKey,
  });

  final bool enabled;

  /// Names of already-staged attachments, for duplicate detection. Read at
  /// pick time so it's always current.
  final Set<String> Function() existingNames;

  /// Called with the validated attachments to stage.
  final ValueChanged<List<ChatAttachment>> onAdded;

  /// Desktop-only: when set, a "Folder" option appears that lets the user
  /// attach a folder for the agent to read. Null on mobile/web (no option).
  final Future<void> Function()? onPickFolder;

  /// Key applied to the inner [IconButton] (E2E tests locate it by key).
  final Key? buttonKey;

  @override
  State<AttachMenuButton> createState() => _AttachMenuButtonState();
}

class _AttachMenuButtonState extends State<AttachMenuButton> {
  final MenuController _menuController = MenuController();

  List<_AttachOption> get _options => [
    if (FilePickerHelper.isMobilePlatform)
      _AttachOption(
        icon: Icons.photo_camera_outlined,
        label: AppLocalizations.of(context)!.titleTakePhoto,
        pick: FilePickerHelper.takePhoto,
      ),
    _AttachOption(
      icon: Icons.photo_library_outlined,
      label: AppLocalizations.of(context)!.titlePhotos,
      pick: FilePickerHelper.pickImages,
    ),
    _AttachOption(
      icon: Icons.folder_outlined,
      label: AppLocalizations.of(context)!.titleFiles,
      pick: FilePickerHelper.pickFiles,
    ),
  ];

  /// Desktop-only: whether to show the "Folder" attach option.
  bool get _showFolder => widget.onPickFolder != null && PlatformInfo.isDesktop;

  Future<void> _runFolder() async {
    await widget.onPickFolder?.call();
  }

  Future<void> _runPick(_AttachOption option) async {
    final result = await option.pick(existingNames: widget.existingNames());
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    for (final error in result.validationErrors) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
    if (result.rejected.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.messageFilesTooLarge(result.rejected.join('\n')),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (result.added.isNotEmpty) {
      widget.onAdded(result.added);
    }
  }

  Future<void> _showSheet() async {
    final option = await showModalBottomSheet<_AttachOption>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _options)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.label),
                onTap: () => Navigator.of(ctx).pop(option),
              ),
            if (_showFolder)
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(AppLocalizations.of(ctx)!.titleFolder),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _runFolder();
                },
              ),
          ],
        ),
      ),
    );
    if (option != null && mounted) await _runPick(option);
  }

  Widget _buildButton({required VoidCallback? onPressed}) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      key: widget.buttonKey,
      onPressed: onPressed,
      icon: const Icon(Icons.attach_file, size: 22),
      tooltip: AppLocalizations.of(context)!.messageAttachPhotosOrFiles,
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
      ),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return _buildButton(onPressed: widget.enabled ? _showSheet : null);
    }

    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        for (final option in _options)
          MenuItemButton(
            leadingIcon: Icon(option.icon, size: 20),
            onPressed: () => _runPick(option),
            child: Text(option.label),
          ),
        if (_showFolder)
          MenuItemButton(
            leadingIcon: const Icon(Icons.create_new_folder_outlined, size: 20),
            onPressed: _runFolder,
            child: Text(AppLocalizations.of(context)!.titleFolder),
          ),
      ],
      builder: (context, controller, _) => _buildButton(
        onPressed: widget.enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
      ),
    );
  }
}

class _AttachOption {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.pick,
  });

  final IconData icon;
  final String label;
  final Future<FilePickResult?> Function({required Set<String> existingNames})
  pick;
}
