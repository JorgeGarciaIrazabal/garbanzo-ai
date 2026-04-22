import 'package:flutter/foundation.dart';

import '../models/knowledge_document.dart';
import '../services/knowledge_base_service.dart';

class KnowledgeBaseProvider extends ChangeNotifier {
  KnowledgeBaseProvider({KnowledgeBaseService? service})
      : _service = service ?? KnowledgeBaseService.instance;

  final KnowledgeBaseService _service;

  List<KnowledgeDocument> _documents = [];
  bool _isLoading = false;
  String? _error;

  List<KnowledgeDocument> get documents => _documents;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasProcessingDocuments =>
      _documents.any((d) => d.isProcessing);

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _documents = await _service.listDocuments();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<KnowledgeDocument?> upload({
    required String filename,
    required List<int> bytes,
    String? mimeType,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final doc = await _service.uploadDocument(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
      );
      _documents = [doc, ..._documents];
      return doc;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> delete(String documentId) async {
    _error = null;
    try {
      await _service.deleteDocument(documentId);
      _documents = _documents.where((d) => d.id != documentId).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
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
