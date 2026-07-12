import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:garbanzo_ai/core/widgets/brand_mark.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/widgets/animated_dialog.dart';
import 'package:garbanzo_ai/core/widgets/skeleton.dart';
import 'package:garbanzo_ai/features/knowledge_base/models/knowledge_document.dart';
import 'package:garbanzo_ai/features/knowledge_base/providers/knowledge_base_provider.dart';

class KnowledgeBasePage extends StatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  // App-level provider (see main.dart); the embedding-progress poll timer
  // stays page-scoped so it stops as soon as the page is closed.
  KnowledgeBaseProvider get _provider => context.read<KnowledgeBaseProvider>();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.refresh();
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollProcessing(),
    );
  }

  Future<void> _pollProcessing() async {
    if (!mounted) return;
    if (_provider.hasProcessingDocuments) {
      await _provider.refreshProcessing();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'txt',
        'md',
        'csv',
        'json',
        'xml',
        'yaml',
        'yml',
        'html',
        'htm',
        'pdf',
        'xlsx',
        'xls',
        'ods',
        'py',
        'js',
        'ts',
        'dart',
        'rs',
        'go',
        'java',
      ],
    );
    if (picked == null) return;

    for (final file in picked.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      await _provider.upload(
        filename: file.name,
        bytes: bytes,
        mimeType: _mimeFromName(file.name),
      );
      if (_provider.error != null && mounted) {
        _showSnack(_provider.error!);
        _provider.clearError();
      }
    }
  }

  String? _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.csv')) return 'text/csv';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (n.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (n.endsWith('.ods')) {
      return 'application/vnd.oasis.opendocument.spreadsheet';
    }
    if (n.endsWith('.json')) return 'application/json';
    if (n.endsWith('.html') || n.endsWith('.htm')) return 'text/html';
    return 'text/plain';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(KnowledgeDocument doc) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document'),
        content: Text('Remove "${doc.filename}" from your knowledge base?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _provider.delete(doc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KnowledgeBaseProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (provider.documents.isEmpty && provider.isLoading) {
            return const SkeletonList(showAvatar: true);
          }
          if (provider.documents.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: provider.documents.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _DocumentTile(
                doc: provider.documents[i],
                onDelete: () => _confirmDelete(provider.documents[i]),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: provider.isLoading ? null : _pickAndUpload,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandMark(size: 72),
            const SizedBox(height: 16),
            Text('No documents yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Upload PDFs, spreadsheets, or text files to make them available '
              'across every conversation.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc, required this.onDelete});

  final KnowledgeDocument doc;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(_iconFor(doc), color: theme.colorScheme.primary),
      title: Text(doc.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_subtitleFor(doc)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusChip(status: doc.status),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  IconData _iconFor(KnowledgeDocument d) {
    final n = d.filename.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (n.endsWith('.csv') ||
        n.endsWith('.xlsx') ||
        n.endsWith('.xls') ||
        n.endsWith('.ods')) {
      return Icons.table_chart;
    }
    return Icons.description;
  }

  String _subtitleFor(KnowledgeDocument d) {
    final size = _formatBytes(d.fileSize);
    final chunks = '${d.chunkCount} chunks';
    if (d.isFailed && d.errorMessage != null) {
      return 'Failed: ${d.errorMessage}';
    }
    return '$size · $chunks';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label, icon) = switch (status) {
      'ready' => (Colors.green, 'Ready', Icons.check_circle),
      'failed' => (Colors.red, 'Failed', Icons.error),
      _ => (theme.colorScheme.primary, 'Processing', Icons.hourglass_top),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        avatar: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
        backgroundColor: color.withAlpha(30),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide.none,
      ),
    );
  }
}
