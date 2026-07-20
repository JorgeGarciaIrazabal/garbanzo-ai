import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';
import 'package:garbanzo_ai/features/chat/services/folder_walk.dart';
import 'package:garbanzo_ai/features/chat/services/folder_writer.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_service.dart';

/// Outcome of writing a finished run's diff back into the local folder.
class ApplyResult {
  const ApplyResult({
    required this.applied,
    required this.conflicts,
    required this.skipped,
    required this.failed,
  });

  /// Files written or deleted successfully.
  final List<String> applied;

  /// Files whose local content changed while the workflow was running — left
  /// untouched rather than clobbering the user's edits.
  final List<String> conflicts;

  /// Changes the server couldn't send back in full (e.g. too large).
  final List<String> skipped;

  /// Files that failed to write (permissions, path escape, …).
  final List<String> failed;

  bool get isClean => conflicts.isEmpty && failed.isEmpty && skipped.isEmpty;
  int get total =>
      applied.length + conflicts.length + skipped.length + failed.length;
}

/// Phase of the client-side work around a run, which the server's `status`
/// doesn't cover (uploading happens before the run exists server-side).
enum WorkflowPhase { idle, walking, uploading, watching, done, failed }

/// Drives delegated opencode workflows (idea 18) from the client side.
///
/// Lives above the message list on purpose: a chat bubble gets disposed as
/// soon as it scrolls out of view, and a workflow runs for minutes. Keeping
/// state here means progress survives scrolling, and polling keeps going while
/// the user reads the rest of the conversation.
class WorkflowProvider extends ChangeNotifier {
  WorkflowProvider({
    WorkflowService? service,
    FolderReader reader = const FolderReader(),
    FolderWriter writer = const FolderWriter(),
  }) : _service = service ?? WorkflowService.instance,
       _reader = reader,
       _writer = writer;

  final WorkflowService _service;
  final FolderReader _reader;
  final FolderWriter _writer;

  /// How often a live run is polled. Fast enough to feel live, slow enough
  /// that a 15-minute run is ~600 requests rather than tens of thousands.
  static const Duration pollInterval = Duration(milliseconds: 1500);

  final Map<String, WorkflowRun> _runs = {};
  final Map<String, WorkflowPhase> _phases = {};
  final Map<String, double> _uploadProgress = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _runIdByToolCall = {};
  final Map<String, Timer> _pollers = {};

  /// Conversations already hydrated, so N cards on screen trigger one fetch.
  final Set<String> _loadedConversations = {};

  WorkflowRun? runFor(String toolCallId) {
    final id = _runIdByToolCall[toolCallId];
    return id == null ? null : _runs[id];
  }

  WorkflowPhase phaseFor(String toolCallId) =>
      _phases[toolCallId] ?? WorkflowPhase.idle;

  double uploadProgressFor(String toolCallId) =>
      _uploadProgress[toolCallId] ?? 0;

  String? errorFor(String toolCallId) => _errors[toolCallId];

  @override
  void dispose() {
    for (final timer in _pollers.values) {
      timer.cancel();
    }
    _pollers.clear();
    super.dispose();
  }

  /// Re-attach cards to their runs after a reload.
  ///
  /// The proposal card only knows its `tool_call_id`; the server stores that
  /// on the run, so one list call restores every card in the conversation —
  /// including runs that finished while the app was closed.
  Future<void> loadForConversation(
    String conversationId, {
    bool force = false,
  }) async {
    if (!force && !_loadedConversations.add(conversationId)) return;
    try {
      final runs = await _service.listForConversation(conversationId);
      for (final run in runs) {
        _runs[run.id] = run;
        final toolCallId = run.toolCallId;
        if (toolCallId == null) continue;
        _runIdByToolCall[toolCallId] = run.id;
        _phases[toolCallId] = switch (run.status) {
          'done' => WorkflowPhase.done,
          'error' || 'cancelled' => WorkflowPhase.failed,
          _ => WorkflowPhase.watching,
        };
        if (run.error != null) _errors[toolCallId] = run.error!;
        if (run.isRunning) _startPolling(toolCallId, run.id);
      }
      notifyListeners();
    } catch (e) {
      // Let a failed hydrate be retried on the next card build.
      _loadedConversations.remove(conversationId);
      logDebug('Could not load workflow runs: $e');
    }
  }

  /// Confirm a `delegate_workflow` proposal: snapshot the folder, upload it,
  /// and start the detached run.
  ///
  /// Everything before [WorkflowService.start] is client-side work on the
  /// user's machine — the backend only ever receives uploaded bytes.
  Future<WorkflowRun?> startFromProposal({
    required String toolCallId,
    required String instruction,
    required String folderRoot,
    String? conversationId,
    String? roomId,
  }) async {
    _errors.remove(toolCallId);
    _setPhase(toolCallId, WorkflowPhase.walking);
    try {
      final FolderWalk walk = _reader.walk(folderRoot);
      if (walk.isEmpty) {
        throw const FolderReadError(
          'The attached folder has no readable files to work on.',
        );
      }

      final run = await _service.create(
        instruction: instruction,
        conversationId: conversationId,
        roomId: roomId,
        toolCallId: toolCallId,
        folderLabel: folderRoot.split(RegExp(r'[/\\]')).last,
      );
      _runs[run.id] = run;
      _runIdByToolCall[toolCallId] = run.id;

      _setPhase(toolCallId, WorkflowPhase.uploading);
      await _uploadSnapshot(toolCallId, run.id, folderRoot, walk);

      final started = await _service.start(run.id);
      _runs[started.id] = started;
      _setPhase(toolCallId, WorkflowPhase.watching);
      _startPolling(toolCallId, started.id);
      return started;
    } catch (e) {
      _errors[toolCallId] = e is FolderReadError ? e.message : e.toString();
      _setPhase(toolCallId, WorkflowPhase.failed);
      return null;
    }
  }

  Future<void> _uploadSnapshot(
    String toolCallId,
    String runId,
    String root,
    FolderWalk walk,
  ) async {
    var batch = <({String path, List<int> bytes})>[];
    var batchBytes = 0;
    var uploaded = 0;

    Future<void> flush() async {
      if (batch.isEmpty) return;
      await _service.uploadFiles(runId, batch);
      uploaded += batch.length;
      _uploadProgress[toolCallId] = uploaded / walk.paths.length;
      notifyListeners();
      batch = [];
      batchBytes = 0;
    }

    for (final path in walk.paths) {
      final List<int> bytes;
      try {
        bytes = _reader.readFile(root, path).bytes;
      } on FolderReadError {
        continue; // vanished or unreadable since the walk — skip it
      }
      batch.add((path: path, bytes: bytes));
      batchBytes += bytes.length;
      if (batchBytes >= WorkflowService.uploadBatchBytes) await flush();
    }
    await flush();
  }

  void _startPolling(String toolCallId, String runId) {
    _pollers[toolCallId]?.cancel();
    // Guards against overlapping ticks: a poll slower than the interval would
    // otherwise start a second request with the same `since` cursor and append
    // the same chunks twice.
    var inFlight = false;
    _pollers[toolCallId] = Timer.periodic(pollInterval, (timer) async {
      if (inFlight) return;
      inFlight = true;
      try {
        final known = _runs[runId];
        final since = known?.progressTotal ?? 0;
        final update = await _service.get(runId, since: since);
        // The response carries only new chunks; stitch them onto what we have
        // so the timeline keeps growing instead of resetting each poll.
        final merged = update.copyWith(
          progress: [...?known?.progress, ...update.progress],
        );
        _runs[runId] = merged;
        if (merged.isTerminal) {
          timer.cancel();
          _pollers.remove(toolCallId);
          _setPhase(
            toolCallId,
            merged.succeeded ? WorkflowPhase.done : WorkflowPhase.failed,
          );
          if (merged.error != null) _errors[toolCallId] = merged.error!;
        }
        notifyListeners();
      } catch (e) {
        logDebug('Workflow poll failed: $e');
      } finally {
        inFlight = false;
      }
    });
  }

  Future<List<WorkflowChange>> fetchChanges(String runId) =>
      _service.getChanges(runId);

  /// Write a finished run's changes into the local folder.
  ///
  /// Each file is applied only if it still matches the content that was
  /// uploaded; anything the user edited in the meantime is reported as a
  /// conflict and left alone. Nothing here is undoable, so the caller must
  /// have shown the user this list first.
  Future<ApplyResult> applyChanges({
    required String runId,
    required String folderRoot,
    required List<WorkflowChange> changes,
    Set<String>? only,
  }) async {
    final applied = <String>[];
    final conflicts = <String>[];
    final skipped = <String>[];
    final failed = <String>[];

    for (final change in changes) {
      if (only != null && !only.contains(change.path)) continue;
      if (!change.isApplicable) {
        skipped.add(change.path);
        continue;
      }
      final localHash = _writer.hashFile(folderRoot, change.path);
      if (_isConflict(change, localHash)) {
        conflicts.add(change.path);
        continue;
      }
      try {
        if (change.isDelete) {
          _writer.deleteFile(folderRoot, change.path);
        } else {
          _writer.writeFile(
            folderRoot,
            change.path,
            base64Decode(change.data!),
          );
        }
        applied.add(change.path);
      } catch (e) {
        logDebug('Could not apply ${change.path}: $e');
        failed.add(change.path);
      }
    }

    if (applied.isNotEmpty || conflicts.isEmpty) {
      // Only release the server-side snapshot once there's nothing left to
      // retry from it.
      try {
        if (conflicts.isEmpty && failed.isEmpty) {
          await _service.markApplied(runId);
        }
      } catch (e) {
        logDebug('Could not release workflow snapshot: $e');
      }
    }

    notifyListeners();
    return ApplyResult(
      applied: applied,
      conflicts: conflicts,
      skipped: skipped,
      failed: failed,
    );
  }

  /// A change conflicts when the local file no longer matches what was
  /// uploaded — including a "new" file that now exists locally.
  bool _isConflict(WorkflowChange change, String? localHash) {
    if (change.baseSha256 == null) {
      // Added by the workflow: safe only if nothing is there now.
      return !change.isDelete && localHash != null;
    }
    // Deleting something already gone is fine; anything else must match.
    if (localHash == null) return !change.isDelete;
    return localHash != change.baseSha256;
  }

  void _setPhase(String toolCallId, WorkflowPhase phase) {
    _phases[toolCallId] = phase;
    notifyListeners();
  }
}
