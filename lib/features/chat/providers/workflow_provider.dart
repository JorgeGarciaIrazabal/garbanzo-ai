import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';
import 'package:garbanzo_ai/features/chat/services/folder_walk.dart';
import 'package:garbanzo_ai/features/chat/services/folder_writer.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_service.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_output_downloader.dart';

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

  static const ApplyResult empty = ApplyResult(
    applied: [],
    conflicts: [],
    skipped: [],
    failed: [],
  );

  /// (De)serialization for the per-run apply record in `SharedPreferences`,
  /// so a reload can show the real outcome (files and counts) instead of a
  /// reconstructed approximation.
  Map<String, dynamic> toJson() => {
    'applied': applied,
    'conflicts': conflicts,
    'skipped': skipped,
    'failed': failed,
  };

  factory ApplyResult.fromJson(Map<String, dynamic> json) => ApplyResult(
    applied: _paths(json['applied']),
    conflicts: _paths(json['conflicts']),
    skipped: _paths(json['skipped']),
    failed: _paths(json['failed']),
  );

  static List<String> _paths(Object? value) =>
      value is List ? value.map((e) => e.toString()).toList() : const [];
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
    required ChatProvider chat,
    WorkflowService? service,
    FolderReader reader = const FolderReader(),
    FolderWriter writer = const FolderWriter(),
    WorkflowOutputDownloader outputDownloader =
        const WorkflowOutputDownloader(),
    this.maxSnapshotFiles = 2000,
    this.maxSnapshotBytes = 50 * 1024 * 1024,
  }) : _chat = chat,
       _service = service ?? WorkflowService.instance,
       _reader = reader,
       _writer = writer,
       _outputDownloader = outputDownloader;

  /// The chat provider that owns the per-conversation attached-folder path
  /// and the current-conversation id. Held so the auto-apply kicked off
  /// inside [WorkflowProvider] can resolve the folder without a
  /// `BuildContext` (a card may be mid-deactivation when it fires).
  final ChatProvider _chat;

  final WorkflowService _service;
  final FolderReader _reader;
  final FolderWriter _writer;
  final WorkflowOutputDownloader _outputDownloader;

  /// Snapshot budgets, mirroring the backend's upload caps.
  final int maxSnapshotFiles;
  final int maxSnapshotBytes;

  /// Called with the run's conversation id when a run reaches a terminal
  /// state.
  ///
  /// The backend writes the run's summary into the conversation as an
  /// assistant message, but the client has no reason to re-fetch on its own —
  /// so the user got an FCM notification saying the workflow had finished and
  /// then found nothing in the chat. Wired in `main.dart` to reload the
  /// conversation.
  void Function(String conversationId)? onRunFinished;

  /// Result of the auto-apply that ran when a finished workflow's diff was
  /// written back into the local folder. `null` until that's happened (or
  /// until we've established there's nothing to apply), so the tile can tell
  /// the user the diff was applied and call out any conflicts/failed writes.
  final Map<String, ApplyResult> _applyResults = {};

  ApplyResult? applyResultFor(String toolCallId) {
    final id = _runIdByToolCall[toolCallId];
    return id == null ? null : _applyResults[id];
  }

  /// SharedPreferences key under which every run that has been auto-applied
  /// (or knowingly skipped) is recorded, runId → the [ApplyResult] as JSON.
  /// A re-attach after reload reads this so a finished run doesn't get
  /// re-applied (its snapshot may already have been released) and so the tile
  /// can show the real outcome instead of a reconstruction.
  static const String _appliedRunsPrefsKey = 'workflow_applied_runs';

  /// The record can only grow (one entry per finished run, forever), so the
  /// oldest entries are dropped past this point. Any run old enough to fall
  /// off has long lost its snapshot server-side anyway.
  static const int _maxAppliedRunRecords = 50;

  final Map<String, ApplyResult> _appliedRuns = {};

  /// Memoized so concurrent callers share one load and a `_markAppliedRun`
  /// can never save before the existing records are in memory (which would
  /// silently clobber them).
  Future<void>? _appliedRunsLoad;

  Future<void> _loadAppliedRuns() => _appliedRunsLoad ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_appliedRunsPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _appliedRuns[entry.key] = ApplyResult.fromJson(value);
          }
        }
      }
    } catch (e) {
      logDebug('Could not load applied-run records: $e');
    }
  }();

  Future<void> _markAppliedRun(String runId, ApplyResult result) async {
    await _loadAppliedRuns();
    _appliedRuns[runId] = result;
    while (_appliedRuns.length > _maxAppliedRunRecords) {
      _appliedRuns.remove(_appliedRuns.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _appliedRunsPrefsKey,
        jsonEncode(_appliedRuns.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (e) {
      logDebug('Could not persist applied-run record: $e');
    }
  }

  /// How often a live run is polled. Fast enough to feel live, slow enough
  /// that a 15-minute run is ~600 requests rather than tens of thousands.
  static const Duration pollInterval = Duration(milliseconds: 1500);

  final Map<String, WorkflowRun> _runs = {};
  final Map<String, WorkflowPhase> _phases = {};
  final Map<String, double> _uploadProgress = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _runIdByToolCall = {};
  final Map<String, ({int skipped, bool truncated})> _snapshotGaps = {};
  final Map<String, Timer> _pollers = {};

  /// A proposal tile can be rebuilt while its first start request is awaiting
  /// the server. Share that request across tile instances so one proposal
  /// cannot create two detached agent runs.
  final Map<String, Future<WorkflowRun?>> _startsInFlight = {};

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

  /// Files left out of the uploaded snapshot, if any — the agent can't see
  /// them, so the UI says so rather than implying full coverage.
  ({int skipped, bool truncated})? snapshotGapFor(String toolCallId) =>
      _snapshotGaps[toolCallId];

  @override
  void dispose() {
    _isDisposed = true;
    for (final timer in _pollers.values) {
      timer.cancel();
    }
    _pollers.clear();
    super.dispose();
  }

  bool _isDisposed = false;

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
    await _loadAppliedRuns();
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
        if (run.isRunning) {
          _startPolling(toolCallId, run.id);
        } else if (run.status == 'done') {
          final recorded = _appliedRuns[run.id];
          if (recorded == null) {
            // Finished while the app was closed: apply now (the snapshot was
            // kept server-side), exactly like a run that finishes on-screen.
            unawaited(_maybeApplyOnDone(run));
          } else {
            // Already applied on a previous launch — restore the recorded
            // result so the tile shows what actually happened instead of
            // applying again.
            _applyResults[run.id] = recorded;
          }
        }
      }
      notifyListeners();
    } catch (e) {
      // Let a failed hydrate be retried on the next card build.
      _loadedConversations.remove(conversationId);
      logDebug('Could not load workflow runs: $e');
    }
  }

  /// Start a detached `delegate_workflow` task, optionally uploading a folder
  /// snapshot before launch.
  ///
  /// Everything before [WorkflowService.start] is client-side work on the
  /// user's machine — the backend only ever receives uploaded bytes.
  Future<WorkflowRun?> startFromProposal({
    required String toolCallId,
    required String instruction,
    String? folderRoot,
    String? conversationId,
    String? roomId,
  }) {
    final inFlight = _startsInFlight[toolCallId];
    if (inFlight != null) return inFlight;

    final completer = Completer<WorkflowRun?>();
    _startsInFlight[toolCallId] = completer.future;

    Future<void> start() async {
      try {
        completer.complete(
          await _startFromProposal(
            toolCallId: toolCallId,
            instruction: instruction,
            folderRoot: folderRoot,
            conversationId: conversationId,
            roomId: roomId,
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_startsInFlight[toolCallId], completer.future)) {
          _startsInFlight.remove(toolCallId)?.ignore();
        }
      }
    }

    unawaited(start());
    return completer.future;
  }

  Future<WorkflowRun?> _startFromProposal({
    required String toolCallId,
    required String instruction,
    String? folderRoot,
    String? conversationId,
    String? roomId,
  }) async {
    _errors.remove(toolCallId);
    final isResearch = folderRoot == null;
    _setPhase(
      toolCallId,
      isResearch ? WorkflowPhase.idle : WorkflowPhase.walking,
    );
    try {
      FolderWalk? walk;
      if (!isResearch) {
        walk = _reader.walk(
          folderRoot,
          maxFiles: maxSnapshotFiles,
          maxTotalBytes: maxSnapshotBytes,
        );
        if (walk.isEmpty) {
          throw const FolderReadError(
            'The attached folder has no readable files to work on.',
          );
        }
      }
      // Anything left out of the snapshot is something the agent will never
      // see — large binaries (a big .pptx/.xlsx clears the 5 MB per-file cap
      // easily) or files past the folder budget. Surfacing this beats letting
      // the user assume the whole project was sent.
      if (walk != null) {
        _snapshotGaps[toolCallId] = (
          skipped: walk.skipped.length,
          truncated: walk.truncated,
        );
      }

      final run = await _service.create(
        instruction: instruction,
        mode: isResearch ? 'research' : 'folder',
        conversationId: conversationId,
        roomId: roomId,
        toolCallId: toolCallId,
        folderLabel: folderRoot?.split(RegExp(r'[/\\]')).last,
      );
      _runs[run.id] = run;
      _runIdByToolCall[toolCallId] = run.id;

      if (walk != null) {
        _setPhase(toolCallId, WorkflowPhase.uploading);
        await _uploadSnapshot(toolCallId, run.id, folderRoot!, walk);
      }

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
          final conversationId = merged.conversationId;
          if (merged.succeeded) {
            // Auto-apply the diff to the user's folder; the tile shows the
            // result. Replaced what used to be a manual "Review changes"
            // gate — Jorge: a revert native action covers undo instead.
            unawaited(_maybeApplyOnDone(merged));
          }
          if (conversationId != null) onRunFinished?.call(conversationId);
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

  /// Export a finished research report without touching folder I/O.
  Future<void> downloadOutput(WorkflowRun run, {required String title}) async {
    final markdown = await _service.getOutput(run.id);
    await _outputDownloader.download(
      markdown: markdown,
      filename: 'research-${run.id}.md',
      title: title,
    );
  }

  /// Runs whose auto-apply is currently in flight, so the poll-terminal path
  /// and a concurrent `loadForConversation` can't both write the same diff.
  final Set<String> _applying = {};

  /// Auto-apply a finished run's diff into the attached folder.
  ///
  /// Replaces what used to be a manual "Review changes → pick → Apply" gate
  /// (Jorge: "let's not have the diff review, let's just apply" — undo is a
  /// separate revert native action, see IDEAS.md). Idempotent per run: once a
  /// result has been recorded the run is never applied again, so a card
  /// scrolling back into view (or a reload) doesn't re-write files. A failed
  /// attempt records nothing, so the next launch retries.
  Future<void> _maybeApplyOnDone(WorkflowRun run) async {
    if (run.status != 'done' || _isDisposed) return;
    if (run.isResearch) return;
    await _loadAppliedRuns();
    if (_appliedRuns.containsKey(run.id)) return;
    if (!_applying.add(run.id)) return;
    try {
      // A run without a conversation has no folder to resolve — and the null
      // id must not pick up a *pending* folder meant for a different, not-
      // yet-started chat.
      final folder = run.conversationId == null
          ? null
          : _chat.clientFolderFor(run.conversationId);
      if (folder == null) {
        // No folder on this device — the user attached it elsewhere, or has
        // since detached it. Record the skip so we don't retry every poll.
        await _markAppliedRun(run.id, ApplyResult.empty);
        if (_isDisposed) return;
        _applyResults[run.id] = ApplyResult.empty;
        notifyListeners();
        return;
      }
      final changes = await _service.getChanges(run.id);
      if (_isDisposed) return;
      final result = await applyChanges(
        runId: run.id,
        folderRoot: folder,
        changes: changes,
      );
      _applyResults[run.id] = result;
      await _markAppliedRun(run.id, result);
      if (_isDisposed) return;
      notifyListeners();
    } catch (e) {
      logDebug('Auto-apply failed for ${run.id}: $e');
    } finally {
      _applying.remove(run.id);
    }
  }

  /// Write a finished run's changes into the local folder.
  ///
  /// Each file is applied only if it still matches the content that was
  /// uploaded; anything the user edited in the meantime is reported as a
  /// conflict and left alone.
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

    try {
      // Release the server-side snapshot once everything has landed. With
      // auto-apply this is now the common path; a conflict leaves it behind
      // so a future "revert" can still inspect it.
      if (conflicts.isEmpty && failed.isEmpty) {
        await _service.markApplied(runId);
      }
    } catch (e) {
      logDebug('Could not release workflow snapshot: $e');
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
