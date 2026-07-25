@TestOn('vm')
library;

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_service.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_output_downloader.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake ChatService so ChatProvider can be constructed in these tests without
/// making any network calls. Only the bits WorkflowProvider touches (the
/// per-conversation folder map and `currentConversation`) actually matter.
class _FakeChatService extends ChatService {
  _FakeChatService() : super.forTesting();

  final _conversation = Conversation(
    id: 'conv-1',
    title: 'Test',
    model: 'llama3.2',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    messages: const [],
  );

  @override
  Future<Conversation> getConversation(String id, {int? messageLimit, bool silent = false}) async =>
      _conversation;

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 50,
    bool silent = false,
  }) async =>
      ConversationList(items: [_conversation], total: 1, page: 1, pageSize: 50);
}

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
  final List<String> createdModes = [];
  final List<String> outputRequests = [];
  int listCalls = 0;
  Completer<List<WorkflowRun>>? listCompleter;
  Completer<void>? listStarted;

  WorkflowRun _run({
    required String id,
    String status = 'draft',
    List<Map<String, dynamic>> progress = const [],
    int progressTotal = 0,
    String? summary,
    String? error,
    String? conversationId,
    Map<String, dynamic>? scope,
  }) => WorkflowRun(
    id: id,
    userId: 'u@example.com',
    status: status,
    instruction: 'do it',
    toolCallId: 'tc-1',
    conversationId: conversationId,
    scope: scope,
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
    String mode = 'folder',
    String? conversationId,
    String? roomId,
    String? toolCallId,
    String? folderLabel,
  }) async {
    createdModes.add(mode);
    return _run(id: 'run-1', scope: {'mode': mode});
  }

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
    final response =
        pollResponses[pollCount.clamp(0, pollResponses.length - 1)];
    pollCount++;
    return response;
  }

  @override
  Future<List<WorkflowChange>> getChanges(String runId) async => changes;

  @override
  Future<void> markApplied(String runId) async => appliedRuns.add(runId);

  @override
  Future<String> getOutput(String runId) async {
    outputRequests.add(runId);
    return '# Research';
  }

  List<WorkflowRun>? listResponse;

  @override
  Future<List<WorkflowRun>> listForConversation(String conversationId) async {
    listCalls++;
    listStarted?.complete();
    final pending = listCompleter;
    if (pending != null) return pending.future;
    return listResponse ?? [_run(id: 'run-1', status: 'done', summary: 'all good')];
  }
}

class _FakeOutputDownloader extends WorkflowOutputDownloader {
  String? markdown;
  String? filename;
  String? title;

  @override
  Future<void> download({
    required String markdown,
    required String filename,
    required String title,
  }) async {
    this.markdown = markdown;
    this.filename = filename;
    this.title = title;
  }
}

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

String _b64(String text) => base64Encode(utf8.encode(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _FakeWorkflowService service;
  late ChatProvider chat;
  late WorkflowProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('workflow_provider_test');
    service = _FakeWorkflowService();
    chat = ChatProvider(chatService: _FakeChatService());
    provider = WorkflowProvider(chat: chat, service: service);
  });

  tearDown(() {
    provider.dispose();
    chat.dispose();
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
      expect(
        service.uploadBatches.expand((b) => b),
        containsAll(<String>['a.txt', 'b.txt']),
      );
      expect(provider.phaseFor('tc-1'), WorkflowPhase.watching);
      expect(provider.runFor('tc-1')?.id, 'run-1');
      expect(service.createdModes, ['folder']);
    });

    test('starts research without walking or uploading a folder', () async {
      final run = await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'deep research',
        conversationId: 'conv-1',
      );

      expect(run, isNotNull);
      expect(service.createdModes, ['research']);
      expect(service.uploadBatches, isEmpty);
      expect(service.started, ['run-1']);
      expect(provider.phaseFor('tc-1'), WorkflowPhase.watching);
    });

    test('shares concurrent starts for one proposal', () async {
      final runs = await Future.wait([
        provider.startFromProposal(
          toolCallId: 'tc-1',
          instruction: 'deep research',
          conversationId: 'conv-1',
        ),
        provider.startFromProposal(
          toolCallId: 'tc-1',
          instruction: 'deep research',
          conversationId: 'conv-1',
        ),
      ]);

      expect(service.createdModes, ['research']);
      expect(service.started, ['run-1']);
      expect(runs[0]?.id, 'run-1');
      expect(runs[1]?.id, 'run-1');
    });

    test('does not restart a proposal that already has a restored run', () async {
      service.listResponse = [
        service._run(
          id: 'finished-run',
          status: 'done',
          conversationId: 'conv-1',
        ),
      ];
      await provider.loadForConversation('conv-1');

      final run = await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'deep research',
        conversationId: 'conv-1',
      );

      expect(run?.id, 'finished-run');
      expect(service.createdModes, isEmpty);
      expect(service.started, isEmpty);
    });

    test('reports files the snapshot had to leave out', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      // A deck bigger than the per-file cap — the agent will never see it, so
      // the user has to be told rather than assuming full coverage.
      File(
        '${root.path}/deck.pptx',
      ).writeAsBytesSync(List.filled(FolderReader.maxFileBytes + 1, 0));

      await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
      );

      expect(provider.snapshotGapFor('tc-1')?.skipped, 1);
      expect(provider.snapshotGapFor('tc-1')?.truncated, isFalse);
      expect(
        service.uploadBatches.expand((b) => b),
        isNot(contains('deck.pptx')),
      );
    });

    test('reports a folder that exceeded the snapshot budget', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      File('${root.path}/b.txt').writeAsStringSync('beta');

      final tight = WorkflowProvider(
        chat: chat,
        service: service,
        maxSnapshotFiles: 1,
      );
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

    test(
      'reports a conflict instead of clobbering a locally edited file',
      () async {
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
        expect(
          File('${root.path}/edit.txt').readAsStringSync(),
          'user edited this',
        );
        // And the server keeps the snapshot so the diff can be retried.
        expect(service.appliedRuns, isEmpty);
      },
    );

    test(
      'treats an added file that now exists locally as a conflict',
      () async {
        File('${root.path}/new.txt').writeAsStringSync('mine');

        final result = await provider.applyChanges(
          runId: 'run-1',
          folderRoot: root.path,
          changes: [
            WorkflowChange(
              path: 'new.txt',
              status: 'added',
              data: _b64('theirs'),
            ),
          ],
        );

        expect(result.conflicts, ['new.txt']);
        expect(File('${root.path}/new.txt').readAsStringSync(), 'mine');
      },
    );

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

  group('research output', () {
    test('downloads markdown through the platform exporter', () async {
      final downloader = _FakeOutputDownloader();
      final researchProvider = WorkflowProvider(
        chat: chat,
        service: service,
        outputDownloader: downloader,
      );
      addTearDown(researchProvider.dispose);
      final run = service._run(
        id: 'research-1',
        status: 'done',
        scope: {'mode': 'research'},
      );

      await researchProvider.downloadOutput(run, title: 'Research report');

      expect(service.outputRequests, ['research-1']);
      expect(downloader.markdown, '# Research');
      expect(downloader.filename, 'research-research-1.md');
      expect(downloader.title, 'Research report');
    });

    test('does not fetch or apply a diff for a completed research run', () async {
      service.listResponse = [
        service._run(
          id: 'research-1',
          status: 'done',
          conversationId: 'conv-1',
          scope: {'mode': 'research'},
        ),
      ];

      await provider.loadForConversation('conv-1');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(service.appliedRuns, isEmpty);
      expect(provider.applyResultFor('tc-1'), isNull);
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
          conversationId: 'conv-1',
        ),
      ];

      // Auto-apply on done needs a folder attached to the chat conversation.
      await chat.attachClientFolder('conv-1', root.path);
      service.changes = [
        WorkflowChange(path: 'done.txt', status: 'added', data: _b64('done!')),
      ];

      await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'tidy up',
        folderRoot: root.path,
        conversationId: 'conv-1',
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

      // The run was auto-applied: the diff landed in the local folder and
      // the snapshot was released (no manual "Review changes" gate anymore).
      expect(service.appliedRuns, ['run-1']);
      expect(File('${root.path}/done.txt').readAsStringSync(), 'done!');
      expect(provider.applyResultFor('tc-1')?.applied, contains('done.txt'));

      // Polling stopped: no further requests after the terminal response.
      final callsAfterDone = service.pollCount;
      await Future<void>.delayed(WorkflowProvider.pollInterval * 2);
      expect(service.pollCount, callsAfterDone);
    });
  });

  group('completion notification', () {
    test(
      'fires onRunFinished so the chat reloads the summary message',
      () async {
        // Regression: the user got an FCM "workflow finished" push, but the
        // summary the backend wrote into the conversation never appeared —
        // nothing told the client to re-fetch.
        File('${root.path}/a.txt').writeAsStringSync('alpha');
        // Auto-apply needs the chat's folder attached; attach it so the
        // terminal-status apply can actually land.
        await chat.attachClientFolder('conv-1', root.path);
        service.changes = [
          WorkflowChange(path: 'summary.md', status: 'added', data: _b64('s')),
        ];
        final finished = <String>[];
        provider.onRunFinished = finished.add;

        service.pollResponses = [
          service._run(id: 'run-1', status: 'running', progressTotal: 0),
          service._run(
            id: 'run-1',
            status: 'done',
            summary: 'created summary.md',
            conversationId: 'conv-1',
          ),
        ];

        await provider.startFromProposal(
          toolCallId: 'tc-1',
          instruction: 'summarise',
          folderRoot: root.path,
          conversationId: 'conv-1',
        );
        await Future<void>.delayed(
          WorkflowProvider.pollInterval * 2 + const Duration(milliseconds: 400),
        );

        expect(finished, ['conv-1']);
        // The diff was auto-applied on done.
        expect(service.appliedRuns, ['run-1']);
      },
    );

    test('fires on failure too, so the error reaches the chat', () async {
      File('${root.path}/a.txt').writeAsStringSync('alpha');
      final finished = <String>[];
      provider.onRunFinished = finished.add;

      service.pollResponses = [
        service._run(
          id: 'run-1',
          status: 'error',
          error: 'opencode died',
          conversationId: 'conv-1',
        ),
      ];

      await provider.startFromProposal(
        toolCallId: 'tc-1',
        instruction: 'summarise',
        folderRoot: root.path,
        conversationId: 'conv-1',
      );
      await Future<void>.delayed(
        WorkflowProvider.pollInterval + const Duration(milliseconds: 400),
      );

      expect(finished, ['conv-1']);
      expect(provider.phaseFor('tc-1'), WorkflowPhase.failed);
    });
  });

  group('loadForConversation', () {
    test('re-attaches a finished run to its proposal card', () async {
      await provider.loadForConversation('conv-1');

      expect(provider.runFor('tc-1')?.summary, 'all good');
      expect(provider.phaseFor('tc-1'), WorkflowPhase.done);
    });

    test(
      'a reload restores the recorded result instead of re-applying',
      () async {
        // First "session": a finished run whose diff gets auto-applied.
        await chat.attachClientFolder('conv-1', root.path);
        service.listResponse = [
          service._run(id: 'run-1', status: 'done', conversationId: 'conv-1'),
        ];
        service.changes = [
          WorkflowChange(path: 'out.txt', status: 'added', data: _b64('v1')),
        ];
        await provider.loadForConversation('conv-1');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(File('${root.path}/out.txt').readAsStringSync(), 'v1');
        expect(service.appliedRuns, ['run-1']);
        expect(provider.applyResultFor('tc-1')?.applied, ['out.txt']);

        // The user edits the file after the apply. A second "session" (fresh
        // provider, same SharedPreferences) must restore the recorded result —
        // with its real file list — and must NOT write the diff again.
        File('${root.path}/out.txt').writeAsStringSync('user edit');
        final second = WorkflowProvider(chat: chat, service: service);
        addTearDown(second.dispose);
        await second.loadForConversation('conv-1');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(File('${root.path}/out.txt').readAsStringSync(), 'user edit');
        expect(service.appliedRuns, ['run-1']); // no second markApplied
        expect(second.applyResultFor('tc-1')?.applied, ['out.txt']);
      },
    );

    test('does not refetch the same conversation twice', () async {
      var calls = 0;
      final counting = _CountingService(() => calls++);
      final p = WorkflowProvider(chat: chat, service: counting);
      addTearDown(p.dispose);

      await p.loadForConversation('conv-1');
      await p.loadForConversation('conv-1');
      expect(calls, 1);

      await p.loadForConversation('conv-1', force: true);
      expect(calls, 2);
    });

    test('concurrent cards await one in-flight hydration', () async {
      final pending = Completer<List<WorkflowRun>>();
      final started = Completer<void>();
      service.listCompleter = pending;
      service.listStarted = started;

      final first = provider.loadForConversation('conv-1');
      final second = provider.loadForConversation('conv-1');

      await started.future;
      expect(service.listCalls, 1);
      pending.complete([
        service._run(
          id: 'finished-run',
          status: 'done',
          conversationId: 'conv-1',
        ),
      ]);
      await Future.wait([first, second]);

      expect(provider.runFor('tc-1')?.id, 'finished-run');
      expect(provider.phaseFor('tc-1'), WorkflowPhase.done);
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
