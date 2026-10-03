import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_feedback.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class ChatFoldersBar extends StatefulWidget {
  const ChatFoldersBar({
    super.key,
    required this.conversationId,
    required this.isSending,
    required this.ensureConversation,
    this.service,
    this.onAttached,
  });
  final String? conversationId;
  final bool isSending;
  final Future<String> Function() ensureConversation;
  final FoldersService? service;
  final Future<void> Function(String conversationId)? onAttached;
  @override
  State<ChatFoldersBar> createState() => _ChatFoldersBarState();
}

class _ChatFoldersBarState extends State<ChatFoldersBar> {
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
  void didUpdateWidget(covariant ChatFoldersBar oldWidget) {
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
    // The messenger outlives this bar when creating a chat changes routes.
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final folders = await _service.list();
      if (!mounted) return;
      final available = folders
          .where((f) => !_attached.any((a) => a.id == f.id))
          .toList();
      final folder = await showDialog<VirtualFolder>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.foldersAttach),
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
                      onTap: () => Navigator.pop(context, available[index]),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
          ],
        ),
      );
      if (folder == null || !mounted) return;
      final id = await widget.ensureConversation();
      await _service.attach(id, folder.id);
      await widget.onAttached?.call(id);
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: disabled ? null : _attach,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text(l.foldersAttach),
              ),
              IconButton(
                tooltip: l.foldersOpen,
                onPressed: () => _open(),
                icon: const Icon(Icons.folder_open_outlined, size: 20),
              ),
              ..._attached.map(
                (folder) => InputChip(
                  label: Text(folder.name),
                  avatar: const Icon(Icons.folder_outlined, size: 16),
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
  }
}
