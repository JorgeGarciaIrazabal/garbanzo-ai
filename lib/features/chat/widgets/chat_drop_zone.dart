import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/platform_info.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/utils/composer_conversation.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:garbanzo_ai/features/chat/widgets/panel_resize_handle.dart';
import 'package:garbanzo_ai/features/microapps/providers/microapp_panel_controller.dart';
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_panel.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Wraps the chat page in desktop OS file/folder drop + in-app drag-and-drop
/// staging, rendering a full-bleed drop-target overlay while hovered.
class ChatDropZone extends StatefulWidget {
  const ChatDropZone({
    super.key,
    required this.enabled,
    required this.onSnack,
    required this.child,
  });

  /// False when viewing a room (attachments belong to conversations).
  final bool enabled;
  final void Function(String message, {bool error}) onSnack;
  final Widget child;

  @override
  State<ChatDropZone> createState() => _ChatDropZoneState();
}

class _ChatDropZoneState extends State<ChatDropZone> {
  bool _isDragOver = false;

  Future<void> _stageFiles(
    List<RawPickedFile> raw,
    ChatProvider provider,
  ) async {
    final result = await FilePickerHelper.validate(
      files: raw,
      existingNames: {...?provider.pendingAttachments?.map((a) => a.name)},
    );
    if (!mounted) return;
    for (final e in result.validationErrors) {
      widget.onSnack(e);
    }
    if (result.rejected.isNotEmpty) {
      widget.onSnack(
        AppLocalizations.of(
          context,
        )!.messageFilesTooLarge(result.rejected.join('\n')),
        error: true,
      );
    }
    if (result.added.isNotEmpty) provider.addAttachments(result.added);
  }

  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    setState(() => _isDragOver = false);
    final chatProvider = context.read<ChatProvider>();
    if (!chatProvider.hasActiveConversation) {
      widget.onSnack(
        AppLocalizations.of(context)!.messageStartAConversationFirst,
      );
      return;
    }
    final raw = <RawPickedFile>[];
    for (final f in files) {
      if (f is! File) continue;
      raw.add((name: f.path.split('/').last, bytes: await f.readAsBytes()));
    }
    await _stageFiles(raw, chatProvider);
  }

  Future<void> _handleOsDrop(List<DropItem> items) async {
    setState(() => _isDragOver = false);
    if (!widget.enabled) return;
    final chatProvider = context.read<ChatProvider>();
    final folder = items
        .where((i) => FileSystemEntity.isDirectorySync(i.path))
        .firstOrNull;
    if (folder != null) {
      try {
        await chatProvider.attachClientFolder(
          composerConversation(context, listen: false)?.id,
          folder.path,
        );
      } catch (e) {
        debugPrint('ChatDropZone._handleOsDrop folder attach failed: $e');
        if (mounted) {
          widget.onSnack(
            AppLocalizations.of(context)!.messageFolderAttachFailed,
          );
        }
      }
      return;
    }
    await _handleDroppedFiles([for (final i in items) File(i.path)]);
  }

  Widget _wrapDesktopDrop(Widget child) {
    if (!PlatformInfo.isDesktop || !widget.enabled) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      onDragDone: (detail) => _handleOsDrop(detail.files),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return _wrapDesktopDrop(
      DragTarget<List<dynamic>>(
        onWillAcceptWithDetails: (details) {
          if (!widget.enabled) return false;
          if (details.data.isEmpty) return false;
          setState(() => _isDragOver = true);
          return true;
        },
        onLeave: (_) => setState(() => _isDragOver = false),
        onAcceptWithDetails: (details) => _handleDroppedFiles(details.data),
        builder: (context, _, _) {
          return Stack(
            children: [
              widget.child,
              if (_isDragOver)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        border: Border.all(
                          color: colorScheme.primary,
                          width: 4,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_upload,
                                size: 64,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.messageDropFilesHere,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.dropFilesSupportedFormats,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Resizable wide-screen micro-app side pane with drag handle.
class ResizableMicroAppPane extends StatefulWidget {
  const ResizableMicroAppPane({super.key, required this.panel});

  final MicroappPanelController panel;

  @override
  State<ResizableMicroAppPane> createState() => _ResizableMicroAppPaneState();
}

class _ResizableMicroAppPaneState extends State<ResizableMicroAppPane> {
  static const double _minPanelWidth = 320;
  static const double _minChatWidth = 360;

  double? _panelWidth;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final maxW = (screenW - _minChatWidth).clamp(_minPanelWidth, screenW);
    final defaultW = (screenW * 0.6).clamp(_minPanelWidth, maxW);
    final width = (_panelWidth ?? defaultW).clamp(_minPanelWidth, maxW);

    return SizedBox(
      width: width,
      child: Row(
        children: [
          PanelResizeHandle(
            // Accumulate each drag delta against `_panelWidth` (the state) —
            // NOT against `width` (the rendered snapshot captured at build
            // time), so multiple drag events within a frame accumulate cleanly.
            onDrag: (dx) => setState(() {
              final current = _panelWidth ?? defaultW;
              _panelWidth = (current + dx).clamp(_minPanelWidth, maxW);
            }),
            onReset: () => setState(() => _panelWidth = null),
          ),
          Expanded(child: MicroAppPanel(panel: widget.panel)),
        ],
      ),
    );
  }
}

/// Dismissible error banner displayed at the top of the chat area.
class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 120),
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline,
              color: colorScheme.onErrorContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss error',
            icon: Icon(
              Icons.close,
              color: colorScheme.onErrorContainer,
              size: 20,
            ),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
