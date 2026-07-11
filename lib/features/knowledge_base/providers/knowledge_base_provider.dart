import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/knowledge_base/models/knowledge_document.dart';
import 'package:garbanzo_ai/features/knowledge_base/services/knowledge_base_service.dart';

class KnowledgeBaseProvider extends ChangeNotifier with GuardedStateMixin {
  KnowledgeBaseProvider({KnowledgeBaseService? service})
      : _service = service ?? KnowledgeBaseService.instance;

  final KnowledgeBaseService _service;

  List<KnowledgeDocument> _documents = [];

  List<KnowledgeDocument> get documents => _documents;
  bool get hasProcessingDocuments =>
      _documents.any((d) => d.isProcessing);

  Future<void> refresh() async {
    await runGuarded('Failed to load documents', () async {
      _documents = await _service.listDocuments();
    });
  }

  Future<KnowledgeDocument?> upload({
    required String filename,
    required List<int> bytes,
    String? mimeType,
  }) async {
    return runGuarded('Failed to upload document', () async {
      final doc = await _service.uploadDocument(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
      );
      _documents = [doc, ..._documents];
      return doc;
    });
  }

  Future<void> delete(String documentId) async {
    await runGuarded('Failed to delete document', () async {
      await _service.deleteDocument(documentId);
      _documents = _documents.where((d) => d.id != documentId).toList();
    }, trackLoading: false);
  }

  /// Fetch updated status for any still-processing documents. Call on a
  /// timer while the user is looking at the page.
  Future<void> refreshProcessing() async {
    final pending = _documents.where((d) => d.isProcessing).toList();
    if (pending.isEmpty) return;
    bool changed = false;
    for (final doc in pending) {
      try {
        final latest = await _service.getDocument(doc.id);
        final idx = _documents.indexWhere((d) => d.id == doc.id);
        if (idx >= 0 && _documents[idx].status != latest.status) {
          _documents[idx] = latest;
          changed = true;
        }
      } catch (_) {
        // ignore transient errors during polling
      }
    }
    if (changed) notifyListeners();
  }
}
