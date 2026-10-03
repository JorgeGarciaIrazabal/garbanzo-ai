import 'package:flutter/material.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Uses the revision of the bytes displayed, never a newer metadata revision.
class FolderTextDialog extends StatefulWidget {
  const FolderTextDialog({
    super.key,
    required this.service,
    required this.folderId,
    this.file,
  });
  final FoldersService service;
  final String folderId;
  final FolderFile? file;
  @override
  State<FolderTextDialog> createState() => _FolderTextDialogState();
}

class _FolderTextDialogState extends State<FolderTextDialog> {
  final _content = TextEditingController();
  final _path = TextEditingController();
  FolderText? _preview;
  String? _error;
  bool _busy = false;
  bool _conflict = false;

  @override
  void initState() {
    super.initState();
    if (widget.file != null) _load();
  }

  @override
  void dispose() {
    _content.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final first = await widget.service.text(widget.file!);
      final buffer = StringBuffer(first.text);
      var next = first.nextOffset;
      // Editable files must be loaded in full before offering Save. Otherwise
      // saving the first preview page would silently truncate the stored file.
      if (first.editable) {
        while (next != null) {
          final chunk = await widget.service.text(first.file, offset: next);
          if (chunk.file.revision != first.file.revision) {
            throw const FolderException(409, 'File changed while loading');
          }
          buffer.write(chunk.text);
          next = chunk.nextOffset;
        }
      }
      if (!mounted) return;
      setState(() {
        _preview = first.copyWith(nextOffset: next);
        _content.text = buffer.toString();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _more() async {
    setState(() => _busy = true);
    try {
      final chunk = await widget.service.text(
        _preview!.file,
        offset: _preview!.nextOffset!,
      );
      if (chunk.file.revision != _preview!.file.revision) {
        throw const FolderException(409, 'File changed while loading');
      }
      if (mounted) {
        setState(() {
          _content.text += chunk.text;
          _preview = chunk;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.file == null) {
        await widget.service.createText(
          widget.folderId,
          _path.text.trim(),
          _content.text,
        );
      } else {
        await widget.service.saveText(_preview!.file, _content.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _conflict = e is FolderException && e.status == 409;
          _error = _conflict
              ? AppLocalizations.of(context)!.foldersConflict
              : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final editable = widget.file == null || _preview?.editable == true;
    return AlertDialog(
      title: Text(widget.file?.path ?? l.foldersNewText),
      content: SizedBox(
        width: 700,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.file == null)
              TextField(
                controller: _path,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.foldersPath),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!editable && _preview != null) Text(l.foldersReadOnly),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _content,
                readOnly: !editable || _busy,
                expands: true,
                minLines: null,
                maxLines: null,
                decoration: InputDecoration(
                  labelText: l.foldersContent,
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            if (_preview?.nextOffset != null)
              TextButton(
                onPressed: _busy ? null : _more,
                child: Text(l.foldersLoadMore),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.close),
        ),
        if (editable)
          FilledButton(
            onPressed:
                _busy ||
                    _conflict ||
                    (widget.file != null && _preview == null) ||
                    (widget.file == null && _path.text.trim().isEmpty)
                ? null
                : _save,
            child: Text(l.save),
          ),
      ],
    );
  }
}
