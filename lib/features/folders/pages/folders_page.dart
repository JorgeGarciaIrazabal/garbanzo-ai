import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_feedback.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_text_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key, this.initialFolderId, this.service});
  final String? initialFolderId;
  final FoldersService? service;
  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  late final FoldersService _service = widget.service ?? FoldersService();
  List<VirtualFolder> _folders = [];
  Map<String, List<FolderFile>> _files = {};
  String? _selected;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialFolderId;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final folders = await _service.list();
      final entries = await Future.wait(
        folders.map((f) async => MapEntry(f.id, await _service.files(f.id))),
      );
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _files = Map.fromEntries(entries);
        if (!_folders.any((f) => f.id == _selected)) _selected = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) folderError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _name([VirtualFolder? folder]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(folder: folder),
    );
    if (name == null || !mounted) return;
    await _run(() async {
      if (folder == null) {
        final created = await _service.create(name);
        _selected = created.id;
      } else {
        await _service.rename(folder.id, name);
      }
    });
  }

  Future<void> _upload(String id) async {
    final l = AppLocalizations.of(context)!;
    try {
      final picked = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || !mounted) return;
      final existing = _files[id] ?? [];
      final bytes =
          existing.fold<int>(0, (sum, file) => sum + file.sizeBytes) +
          picked.files.fold<int>(0, (sum, file) => sum + file.size);
      if (picked.files.any((file) => file.size > FoldersService.maxFileBytes) ||
          bytes > FoldersService.maxFolderBytes ||
          existing.length + picked.files.length >
              FoldersService.maxFolderFiles) {
        throw FolderException(413, l.foldersLimitExceeded);
      }
      if (picked.files.any((f) => f.bytes == null)) {
        throw FolderException(0, l.foldersBytesUnavailable);
      }
      // Uploads are individual transactions. Refresh even when one fails, so
      // successful files remain visible and the error names the failed file.
      setState(() => _busy = true);
      final errors = <String>[];
      for (final file in picked.files) {
        try {
          await _service.upload(id, file.name, file.bytes!);
        } catch (e) {
          errors.add('${file.name}: $e');
        }
      }
      await _refresh();
      if (errors.isNotEmpty && mounted) folderError(context, errors.join('\n'));
    } catch (e) {
      if (mounted) folderError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _text(String folderId, [FolderFile? file]) async {
    if (file?.mediaType.startsWith('image/') == true) {
      await _run(() async {
        final bytes = await _service.content(file!);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(file.path),
            content: SizedBox(
              width: 700,
              height: 450,
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, error, stack) => Text(error.toString()),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.close),
              ),
            ],
          ),
        );
      });
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          FolderTextDialog(service: _service, folderId: folderId, file: file),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _download(VirtualFolder folder, [FolderFile? file]) async {
    try {
      await _service.download(
        folderId: folder.id,
        fileId: file?.id,
        filename: file?.path.split('/').last ?? '${folder.name}.zip',
        mediaType: file?.mediaType ?? 'application/zip',
        title: AppLocalizations.of(context)!.foldersDownload,
      );
    } catch (e) {
      if (mounted) folderError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final visible = _folders
        .where((f) => _selected == null || f.id == _selected)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.foldersTitle),
        actions: [
          IconButton(
            tooltip: l.foldersRefresh,
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: l.foldersCreate,
            onPressed: _busy ? null : _name,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.foldersSubtitle),
                const SizedBox(height: 8),
                Text(
                  l.foldersLimits,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_folders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_selected),
                      initialValue: _selected ?? '',
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: '', child: Text(l.foldersAll)),
                        ..._folders.map(
                          (f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(f.name),
                          ),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (id) => setState(
                              () => _selected = id == '' ? null : id,
                            ),
                    ),
                  ),
                if (_error != null)
                  Text(
                    l.foldersError(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_folders.isEmpty && !_busy)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.foldersEmpty),
                    ),
                  ...visible.map(
                    (folder) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.folder_outlined),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    folder.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (action) async {
                                    switch (action) {
                                      case 'rename':
                                        await _name(folder);
                                      case 'download':
                                        await _download(folder);
                                      case 'delete':
                                        if (!mounted) return;
                                        if (await confirmFolderDelete(
                                              context,
                                              folder: true,
                                            ) &&
                                            mounted) {
                                          await _run(
                                            () => _service.delete(folder.id),
                                          );
                                        }
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text(l.foldersRename),
                                    ),
                                    PopupMenuItem(
                                      value: 'download',
                                      child: Text(l.foldersDownloadZip),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(l.delete),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _upload(folder.id),
                                  icon: const Icon(Icons.upload_file),
                                  label: Text(l.foldersUpload),
                                ),
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _text(folder.id),
                                  icon: const Icon(Icons.note_add_outlined),
                                  label: Text(l.foldersNewText),
                                ),
                              ],
                            ),
                            if ((_files[folder.id] ?? []).isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(l.foldersFilesEmpty),
                              ),
                            ...(_files[folder.id] ?? []).map(
                              (file) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.insert_drive_file_outlined,
                                ),
                                title: Text(file.path),
                                subtitle: Text(
                                  l.foldersRevision(
                                    file.revision,
                                    file.sizeBytes,
                                  ),
                                ),
                                onTap: _busy
                                    ? null
                                    : () => _text(folder.id, file),
                                trailing: PopupMenuButton<String>(
                                  enabled: !_busy,
                                  onSelected: (action) async {
                                    switch (action) {
                                      case 'preview':
                                        await _text(folder.id, file);
                                      case 'download':
                                        await _download(folder, file);
                                      case 'delete':
                                        if (!mounted) return;
                                        if (await confirmFolderDelete(
                                              context,
                                              folder: false,
                                            ) &&
                                            mounted) {
                                          await _run(
                                            () => _service.deleteFile(file),
                                          );
                                        }
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'preview',
                                      child: Text(l.foldersPreview),
                                    ),
                                    PopupMenuItem(
                                      value: 'download',
                                      child: Text(l.foldersDownload),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(l.delete),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({this.folder});
  final VirtualFolder? folder;
  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _controller = TextEditingController(
    text: widget.folder?.name ?? '',
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.folder == null ? l.foldersCreate : l.foldersRename),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: l.foldersName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l.save),
        ),
      ],
    );
  }
}
