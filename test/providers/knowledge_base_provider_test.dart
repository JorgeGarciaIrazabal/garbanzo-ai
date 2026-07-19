import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/knowledge_base/models/knowledge_document.dart';
import 'package:garbanzo_ai/features/knowledge_base/providers/knowledge_base_provider.dart';
import 'package:garbanzo_ai/features/knowledge_base/services/knowledge_base_service.dart';
import 'package:mocktail/mocktail.dart';

class MockKnowledgeBaseService extends Mock implements KnowledgeBaseService {}

KnowledgeDocument _doc(
  String id, {
  String filename = 'notes.pdf',
  String status = 'ready',
  int chunkCount = 3,
}) {
  return KnowledgeDocument(
    id: id,
    filename: filename,
    mimeType: 'application/pdf',
    fileSize: 1024,
    status: status,
    chunkCount: chunkCount,
    createdAt: DateTime.utc(2026),
  );
}

void main() {
  late MockKnowledgeBaseService service;

  setUp(() {
    service = MockKnowledgeBaseService();
  });

  KnowledgeBaseProvider provider() => KnowledgeBaseProvider(service: service);

  group('refresh', () {
    test('loads documents and clears loading', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1'), _doc('d2')]);

      final p = provider();
      await p.refresh();

      expect(p.documents.map((d) => d.id), ['d1', 'd2']);
      expect(p.error, isNull);
      expect(p.isLoading, isFalse);
    });

    test('surfaces a load failure as a user-facing error', () async {
      when(() => service.listDocuments())
          .thenThrow(Exception('API Error (500): boom'));

      final p = provider();
      await p.refresh();

      expect(p.documents, isEmpty);
      expect(p.error, isNotNull);
      expect(p.isLoading, isFalse);
    });

    test('replaces the list and clears a prior error', () async {
      when(() => service.listDocuments())
          .thenThrow(Exception('API Error (500): boom'));
      final p = provider();
      await p.refresh();
      expect(p.error, isNotNull);

      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1')]);
      await p.refresh();

      expect(p.error, isNull);
      expect(p.documents.single.id, 'd1');
    });
  });

  group('hasProcessingDocuments', () {
    test('is true when any document is pending or processing', () async {
      when(() => service.listDocuments()).thenAnswer(
        (_) async => [_doc('d1'), _doc('d2', status: 'processing')],
      );

      final p = provider();
      await p.refresh();

      expect(p.hasProcessingDocuments, isTrue);
    });

    test('is false when all documents are ready or failed', () async {
      when(() => service.listDocuments()).thenAnswer(
        (_) async => [_doc('d1'), _doc('d2', status: 'failed')],
      );

      final p = provider();
      await p.refresh();

      expect(p.hasProcessingDocuments, isFalse);
    });
  });

  group('upload', () {
    test('prepends the uploaded document and returns it', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('old')]);
      when(
        () => service.uploadDocument(
          filename: any(named: 'filename'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => _doc('new', filename: 'fresh.pdf'));

      final p = provider();
      await p.refresh();
      final result = await p.upload(filename: 'fresh.pdf', bytes: [1, 2, 3]);

      expect(result?.id, 'new');
      expect(p.documents.map((d) => d.id), ['new', 'old']);
    });

    test('keeps the list intact and returns null when upload fails', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('old')]);
      when(
        () => service.uploadDocument(
          filename: any(named: 'filename'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenThrow(Exception('API Error (500): nope'));

      final p = provider();
      await p.refresh();
      final result = await p.upload(filename: 'fresh.pdf', bytes: [1, 2, 3]);

      expect(result, isNull);
      expect(p.error, isNotNull);
      expect(p.documents.map((d) => d.id), ['old']);
    });
  });

  group('delete', () {
    test('removes the document from the list', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1'), _doc('d2')]);
      when(() => service.deleteDocument('d1')).thenAnswer((_) async {});

      final p = provider();
      await p.refresh();
      await p.delete('d1');

      expect(p.documents.map((d) => d.id), ['d2']);
    });

    test('keeps the document when the API call fails', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1')]);
      when(() => service.deleteDocument('d1'))
          .thenThrow(Exception('API Error (500): nope'));

      final p = provider();
      await p.refresh();
      await p.delete('d1');

      expect(p.documents.map((d) => d.id), ['d1']);
      expect(p.error, isNotNull);
    });
  });

  group('refreshProcessing', () {
    test('updates a document whose status changed', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1', status: 'processing')]);
      when(() => service.getDocument('d1'))
          .thenAnswer((_) async => _doc('d1', status: 'ready'));

      final p = provider();
      await p.refresh();
      await p.refreshProcessing();

      expect(p.documents.single.status, 'ready');
      expect(p.hasProcessingDocuments, isFalse);
    });

    test('does nothing when no documents are processing', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1', status: 'ready')]);

      final p = provider();
      await p.refresh();
      await p.refreshProcessing();

      verifyNever(() => service.getDocument(any()));
    });

    test('ignores transient polling errors', () async {
      when(() => service.listDocuments())
          .thenAnswer((_) async => [_doc('d1', status: 'processing')]);
      when(() => service.getDocument('d1'))
          .thenThrow(Exception('API Error (503): unavailable'));

      final p = provider();
      await p.refresh();
      await p.refreshProcessing();

      expect(p.documents.single.status, 'processing');
      expect(p.error, isNull);
    });
  });
}
