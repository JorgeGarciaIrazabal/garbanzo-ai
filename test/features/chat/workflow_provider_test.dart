@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_service.dart';

/// Covers the client half of a delegated workflow (idea 18): snapshot upload,
/// polling/stitching of progress, and — most importantly — the hash-gated
/// write-back that must never clobber a file the user edited mid-run.
class _FakeWorkflowService extends WorkflowService {
  _FakeWorkflowService() : super.forTesting();

  final List<List<String>> uploadBatches = [];
  final List<String> started = [];
  final List<String> appliedRuns = [];
  List<WorkflowRun> pollResponses = [];
  List<WorkflowChange> changes = [];
  int pollCount = 0;
  List<int> sinceValues = [];

  WorkflowRun _run({
    required String id,
    String status = 'draft',
    List<Map<String, dynamic>> progress = const [],
    int progressTotal = 0,
    String? summary,
    String? error,
  }) => WorkflowRun(
    id: id,
    userId: 'u@example.com',
    status: status,
    instruction: 'do it',
    toolCallId: 'tc-1',
    progress: progress,
    progressTotal: progressTotal,
    summary: summary,
    error: error,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<WorkflowRun> create({
    required String instruction,
    String? conversationId,
    String? roomId,
    String? toolCallId,
    String? folderLabel,
  }) async => _run(id: 'run-1');

  @override
  Future<void> uploadFiles(
    String runId,
    List<({String path, List<int> bytes})> files,
  ) async {
    uploadBatches.add(files.map((f) => f.path).toList());
  }

  @override
  Future<WorkflowRun> start(String runId) async {
    started.add(runId);
    return _run(id: runId, status: 'queued');
  }

  @override
  Future<WorkflowRun> get(String runId, {int since = 0}) async {
    sinceValues.add(since);
    final response = pollResponses[pollCount.clamp(
      0,
      pollResponses.length - 1,
    )];
    pollCount++;
    return response;
  }

  @override
  Future<List<WorkflowChange>> getChanges(String runId) async => changes;

  @override
  Future<void> markApplied(String runId) async => appliedRuns.add(runId);

  @override
  Future<List<WorkflowRun>> listForConversation(String conversationId) async =>
      [_run(id: 'run-1', status: 'done', summary: 'all good')];
}

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

String _b64(String text) => base64Encode(utf8.encode(text));

void main() {
  late Directory root;
  late _FakeWorkflowService service;
  late WorkflowProvider provider;

  setUp(() {
    root = Directory.systemTemp.createTempSync('workflow_provider_test');
    service = _FakeWorkflowService();
    provider = WorkflowProvider(service: service);
  });

  tearDown(() {
    provider.dispose();
    root.deleteSync(recursive: true);
  });

  group('startFromProposal', () {
    test('walks, uploads, and starts the run', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      File('${root.path}/b.txt').writeAsStringSync('beta');

      final run = await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      expect(run, isNotNull);
      expect(service.started, ['run-1']);
      expect(service.uploadBatches.expand((b) => b), containsAll(
        <String>['a.txt', 'b.txt'],
      ));
      expect(provider.phaseFor('tc-1'), WorkflowPhase.watching);
      expect(provider.runFor('tc-1')?.id, 'run-1');
    });

    test('reports files the snapshot had to leave out', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      // A deck bigger than the per-file cap — the agent will never see it, so
      // the user has to be told rather than assuming full coverage.
      File('${root.path}/deck.pptx').writeAsBytesSync(
        List.filled(FolderReader.maxFileBytes + 1, 0),
      );

      await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      expect(provider.snapshotGapFor('tc-1')?.skipped, 1);
      expect(provider.snapshotGapFor('tc-1')?.truncated, isFalse);
      expect(service.uploadBatches.expand((b) => b), isNot(contains('deck.pptx')));
    });

    test('reports a folder that exceeded the snapshot budget', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      File('${root.path}/b.txt').writeAsStringSync('beta');

      final tight = WorkflowProvider(service: service, maxSnapshotFiles: 1);
      addTearDown(tight.dispose);
      await tight.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      expect(tight.snapshotGapFor('tc-1')?.truncated, isTrue);
    });

    test('reports no gap when the whole folder fits', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');

      await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      final gap = provider.snapshotGapFor('tc-1')!;
      expect(gap.skipped, 0);
      expect(gap.truncated, isFalse);
    });

    test('fails cleanly when the folder has nothing to upload', () async {
      final run = await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      expect(run, isNull);
      expect(service.started, isEmpty);
      expect(provider.phaseFor('tc-1'), WorkflowPhase.failed);
      expect(provider.errorFor('tc-1'), contains('no readable files'));
    });
  });

  group('applyChanges', () {
    test('writes, overwrites, and deletes files that still match', () async {
      File('${root.path}/edit.txt').writeAsStringSync('before');
      File('${root.path}/gone.txt').writeAsStringSync('bye');

      final result = await provider.applyChanges(
        runId: 'run-1',
        folderRoot: root.path,
        changes: [
          WorkflowChange(path: 'new.txt', status: 'added', data: _b64('fresh')),
          WorkflowChange(
            path: 'edit.txt',
            status: 'modified',
            data: _b64('after'),
            baseSha256: _sha('before'),
          ),
          WorkflowChange(
            path: 'gone.txt',
            status: 'deleted',
            baseSha256: _sha('bye'),
          ),
        ],
      );

      expect(result.applied, hasLength(3));
      expect(result.conflicts, isEmpty);
      expect(result.isClean, isTrue);
      expect(File('${root.path}/new.txt').readAsStringSync(), 'fresh');
      expect(File('${root.path}/edit.txt').readAsStringSync(), 'after');
      expect(File('${root.path}/gone.txt').existsSync(), isFalse);
      // The snapshot is only released when everything landed.
      expect(service.appliedRuns, ['run-1']);
    });

    test('reports a conflict instead of clobbering a locally edited file', () async {
      File('${root.path}/edit.txt').writeAsStringSync('user edited this');

      final result = await provider.applyChanges(
        runId: 'run-1',
        folderRoot: root.path,
        changes: [
          WorkflowChange(
            path: 'edit.txt',
            status: 'modified',
            data: _b64('agent version'),
            baseSha256: _sha('before'),
          ),
        ],
      );

      expect(result.conflicts, ['edit.txt']);
      expect(result.applied, isEmpty);
      // The user's work survives untouched.
      expect(File('${root.path}/edit.txt').readAsStringSync(), 'user edited this');
      // And the server keeps the snapshot so the diff can be retried.
      expect(service.appliedRuns, isEmpty);
    });

    test('treats an added file that now exists locally as a conflict', () async {
      File('${root.path}/new.txt').writeAsStringSync('mine');

      final result = await provider.applyChanges(
        runId: 'run-1',
        folderRoot: root.path,
        changes: [
          WorkflowChange(path: 'new.txt', status: 'added', data: _b64('theirs')),
        ],
      );

      expect(result.conflicts, ['new.txt']);
      expect(File('${root.path}/new.txt').readAsStringSync(), 'mine');
    });

    test('deleting a file that is already gone is not a conflict', () async {
      final result = await provider.applyChanges(
        runId: 'run-1',
        folderRoot: root.path,
        changes: [
          WorkflowChange(
            path: 'gone.txt',
            status: 'deleted',
            baseSha256: _sha('bye'),
          ),
        ],
      );

      expect(result.applied, ['gone.txt']);
      expect(result.conflicts, isEmpty);
    });

    test('skips a change the server could not send back in full', () async {
      final result = await provider.applyChanges(
        runId: 'run-1',
        folderRoot: root.path,
        changes: [
          const WorkflowChange(path: 'huge.bin', status: 'modified', size: 999),
        ],
      );

      expect(result.skipped, ['huge.bin']);
      expect(result.applied, isEmpty);
    });

    test('applies only the selected subset', () async {
      final result = await provider.applyChanges(
        runId: 'run-1',
        folderRoot: root.path,
        changes: [
          WorkflowChange(path: 'a.txt', status: 'added', data: _b64('a')),
          WorkflowChange(path: 'b.txt', status: 'added', data: _b64('b')),
        ],
        only: {'a.txt'},
      );

      expect(result.applied, ['a.txt']);
      expect(File('${root.path}/b.txt').existsSync(), isFalse);
    });
  });

  group('polling', () {
    test('stitches incremental progress and stops when terminal', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      service.pollResponses = [
        service._run(
          id: 'run-1',
          status: 'running',
          progress: [
            {'type': 'chunk', 'content': 'one'},
          ],
          progressTotal: 1,
        ),
        service._run(
          id: 'run-1',
          status: 'done',
          progress: [
            {'type': 'chunk', 'content': 'two'},
          ],
          progressTotal: 2,
          summary: 'finished',
        ),
      ];

      await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      await Future<void>.delayed(
        WorkflowProvider.pollInterval * 2 + const Duration(milliseconds: 400),
      );

      final run = provider.runFor('tc-1')!;
      expect(run.status, 'done');
      expect(run.summary, 'finished');
      // Both chunks are kept — a poll returns only what's new.
      expect(run.progress.map((e) => e['content']), ['one', 'two']);
      // The second poll asked only for what came after the first.
      expect(service.sinceValues.first, 0);
      expect(service.sinceValues[1], 1);
      expect(provider.phaseFor('tc-1'), WorkflowPhase.done);

      // Polling stopped: no further requests after the terminal response.
      final callsAfterDone = service.pollCount;
      await Future<void>.delayed(WorkflowProvider.pollInterval * 2);
      expect(service.pollCount, callsAfterDone);
    });
  });

  group('loadForConversation', () {
    test('re-attaches a finished run to its proposal card', () async {
      await provider.loadForConversation('conv-1');

      expect(provider.runFor('tc-1')?.summary, 'all good');
      expect(provider.phaseFor('tc-1'), WorkflowPhase.done);
    });

    test('does not refetch the same conversation twice', () async {
      var calls = 0;
      final counting = _CountingService(() => calls++);
      final p = WorkflowProvider(service: counting);
      addTearDown(p.dispose);

      await p.loadForConversation('conv-1');
      await p.loadForConversation('conv-1');
      expect(calls, 1);

      await p.loadForConversation('conv-1', force: true);
      expect(calls, 2);
    });
  });
}

class _CountingService extends WorkflowService {
  _CountingService(this.onCall) : super.forTesting();

  final void Function() onCall;

  @override
  Future<List<WorkflowRun>> listForConversation(String conversationId) async {
    onCall();
    return [];
  }
}
