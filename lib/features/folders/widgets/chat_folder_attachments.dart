import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_feedback.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class ChatFolderAttachments extends StatefulWidget {
  const ChatFolderAttachments({
    super.key,
    required this.conversationId,
    required this.isSending,
    required this.ensureConversation,
    this.service,
    this.onAttached,
    required this.builder,
  });

  /// Places persisted-folder chips inside the composer and supplies its menu action.
  final Widget Function(
    BuildContext context,
    Future<void> Function()? attach,
    Widget chips,
  )
  builder;
  final String? conversationId;
  final bool isSending;
  final Future<String> Function() ensureConversation;
  final FoldersService? service;
  final Future<void> Function(String conversationId)? onAttached;
  @override
  State<ChatFolderAttachments> createState() => _ChatFolderAttachmentsState();
}

class _ChatFolderAttachmentsState extends State<ChatFolderAttachments> {
  late final _service = widget.service ?? FoldersService();
  List<VirtualFolder> _attached = [];
  String? _error;
  bool _busy = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatFolderAttachments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _attached = [];
      _error = null;
    }
    if (oldWidget.conversationId != widget.conversationId ||
        (oldWidget.isSending && !widget.isSending)) {
      // Refresh after the whole AI turn, including tool-driven attachments.
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final id = widget.conversationId;
    if (id == null) {
      setState(() {
        _attached = [];
        _error = null;
      });
      return;
    }
    try {
      final folders = await _service.attached(id);
      if (mounted && epoch == _epoch) {
        setState(() {
          _attached = folders;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = e.toString());
    }
  }

  Future<void> _attach() async {
    // The messenger outlives this composer when creating a chat changes routes.
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context)!;
    final startingId = widget.conversationId;
    final ensureConversation = widget.ensureConversation;
    final onAttached = widget.onAttached;
    setState(() => _busy = true);
    try {
      final folders = await _service.list();
      if (!mounted || widget.conversationId != startingId) return;
      final available = folders
          .where((f) => !_attached.any((a) => a.id == f.id))
          .toList();
      final selection =
          await showDialog<({VirtualFolder? folder, bool openFolders})>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l.foldersAttachSaved),
              content: SizedBox(
                width: 440,
                height: 300,
                child: available.isEmpty
                    ? Text(l.foldersAttachEmpty)
                    : ListView.builder(
                        itemCount: available.length,
                        itemBuilder: (_, index) => ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(available[index].name),
                          subtitle: available[index].description.isEmpty
                              ? null
                              : Text(
                                  available[index].description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(context, (
                            folder: available[index],
                            openFolders: false,
                          )),
                        ),
                      ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context, (folder: null, openFolders: true));
                  },
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(l.foldersOpen),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.cancel),
                ),
              ],
            ),
          );
      if (selection == null ||
          !mounted ||
          widget.conversationId != startingId ||
          widget.isSending) {
        return;
      }
      if (selection.openFolders) {
        setState(() => _busy = false);
        await _open();
        return;
      }
      final folder = selection.folder!;
      final id = await ensureConversation();
      await _service.attach(id, folder.id);
      await onAttached?.call(id);
      if (mounted) await _load();
    } catch (e) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.foldersError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detach(VirtualFolder folder) async {
    final id = widget.conversationId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await _service.detach(id, folder.id);
      await _load();
    } catch (e) {
      if (mounted) folderError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open([String? id]) async {
    await context.push('/folders${id == null ? '' : '?folder=$id'}');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final disabled = _busy || widget.isSending;
    final chips = _attached.isEmpty && _error == null && !_busy
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._attached.map(
                      (folder) => InputChip(
                        label: Text(folder.name),
                        avatar: const Icon(Icons.folder_outlined, size: 16),
                        tooltip: folder.description.isEmpty
                            ? l.foldersOpen
                            : folder.description,
                        onPressed: () => _open(folder.id),
                        deleteButtonTooltipMessage: l.foldersDetach,
                        onDeleted: disabled ? null : () => _detach(folder),
                      ),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (_error != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.foldersError(_error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l.foldersRefresh,
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
              ],
            ),
          );
    return widget.builder(context, disabled ? null : _attach, chips);
  }
}
