import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';

/// REST client for delegated opencode workflows (idea 18).
///
/// The flow is deliberately explicit — create, upload, start — so the caller
/// can report upload progress and so nothing executes until the snapshot is
/// complete.
class WorkflowService {
  WorkflowService._();
  static final WorkflowService instance = WorkflowService._();

  /// For tests only: lets a fake subclass exist outside this library.
  @visibleForTesting
  WorkflowService.forTesting();

  final ApiClient _api = ApiClient.instance;

  /// Roughly how many bytes of file content go in one upload request. Base64
  /// inflates by ~33%, so this lands near a 2.7 MB body — big enough to keep
  /// the request count low, small enough to stream progress smoothly.
  static const int uploadBatchBytes = 2 * 1024 * 1024;

  Future<WorkflowRun> create({
    required String instruction,
    String mode = 'folder',
    String? conversationId,
    String? roomId,
    String? toolCallId,
    String? folderLabel,
  }) async {
    final response = await _api.post(
      '/api/v1/workflows',
      data: {
        'instruction': instruction,
        'mode': mode,
        'conversation_id': ?conversationId,
        'room_id': ?roomId,
        'tool_call_id': ?toolCallId,
        'folder_label': ?folderLabel,
      },
    );
    return WorkflowRun.fromJson(response.data as Map<String, dynamic>);
  }

  /// Upload one batch of snapshot files. [files] maps relative path → bytes.
  Future<void> uploadFiles(
    String runId,
    List<({String path, List<int> bytes})> files,
  ) async {
    await _api.post(
      '/api/v1/workflows/$runId/files',
      data: {
        'files': [
          for (final f in files)
            {'path': f.path, 'data': base64Encode(f.bytes)},
        ],
      },
    );
  }

  Future<WorkflowRun> start(String runId) async {
    final response = await _api.post('/api/v1/workflows/$runId/start');
    return WorkflowRun.fromJson(response.data as Map<String, dynamic>);
  }

  /// Poll a run, returning only the progress emitted after [since].
  Future<WorkflowRun> get(String runId, {int since = 0}) async {
    final response = await _api.get(
      '/api/v1/workflows/$runId',
      queryParameters: {'since': since},
    );
    return WorkflowRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<WorkflowRun>> listForConversation(String conversationId) async {
    final response = await _api.get(
      '/api/v1/workflows',
      queryParameters: {'conversation_id': conversationId},
    );
    return (response.data as List)
        .map((e) => WorkflowRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<WorkflowChange>> getChanges(String runId) async {
    final response = await _api.get('/api/v1/workflows/$runId/changes');
    final data = response.data as Map<String, dynamic>;
    return (data['changes'] as List)
        .map((e) => WorkflowChange.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch the durable markdown report produced by a research-mode run.
  Future<String> getOutput(String runId) async {
    final response = await _api.get('/api/v1/workflows/$runId/output');
    return response.data?.toString() ?? '';
  }

  /// Tell the server the diff has been applied so it can drop the snapshot.
  Future<void> markApplied(String runId) async {
    await _api.post('/api/v1/workflows/$runId/applied');
  }
}
