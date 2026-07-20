import 'package:freezed_annotation/freezed_annotation.dart';

part 'workflow_run.freezed.dart';
part 'workflow_run.g.dart';

/// A delegated opencode workflow run (idea 18).
///
/// The run works on a server-side snapshot of the attached folder, so it keeps
/// going even if this app closes — which is why it has a persisted status and
/// a replayable [progress] timeline rather than living in the chat stream.
@freezed
abstract class WorkflowRun with _$WorkflowRun {
  const WorkflowRun._();

  const factory WorkflowRun({
    required String id,
    required String userId,
    String? conversationId,
    String? roomId,
    String? toolCallId,
    required String status,
    required String instruction,
    Map<String, dynamic>? scope,
    String? summary,
    String? error,
    @Default(<Map<String, dynamic>>[]) List<Map<String, dynamic>> progress,
    @Default(0) int progressOffset,
    @Default(0) int progressTotal,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
  }) = _WorkflowRun;

  factory WorkflowRun.fromJson(Map<String, dynamic> json) =>
      _$WorkflowRunFromJson(json);

  /// True once the run can no longer change — stop polling.
  bool get isTerminal =>
      status == 'done' || status == 'error' || status == 'cancelled';

  bool get isRunning => status == 'queued' || status == 'running';

  bool get succeeded => status == 'done';
}

/// One file a finished run created, modified, or deleted.
@freezed
abstract class WorkflowChange with _$WorkflowChange {
  const WorkflowChange._();

  const factory WorkflowChange({
    required String path,
    required String status,

    /// Base64 of the new content; null for deletions (and for files too large
    /// to send back, which are reported as skipped).
    String? data,

    /// sha256 of the content that was uploaded. The local file must still
    /// match this, or the user edited it during the run and applying would
    /// clobber their work.
    String? baseSha256,
    @Default(0) int size,
  }) = _WorkflowChange;

  factory WorkflowChange.fromJson(Map<String, dynamic> json) =>
      _$WorkflowChangeFromJson(json);

  bool get isDelete => status == 'deleted';

  /// A non-delete change with no content can't be applied.
  bool get isApplicable => isDelete || data != null;
}
