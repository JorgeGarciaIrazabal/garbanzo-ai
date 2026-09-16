import 'package:garbanzo_ai/features/chat/models/agent_progress.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

/// Builds [AgentProgress] from the messages/timeline a run has produced.
///
/// The backend already normalizes opencode's frames into a monotonic sequence
/// (a tool reports `started` then `finished`, once each, with its label and
/// duration), so this reducer is deliberately a pure fold over those facts
/// rather than another layer of heuristics. Everything it renders corresponds
/// to an observed action — agent narration is excluded, because it can describe
/// work that never happened.
class AgentProgressBuilder {
  AgentProgressBuilder._();

  /// Build progress from chat tool-call/tool-result messages.
  ///
  /// Used by the in-chat activity rail, where each step arrives as its own
  /// message (a `tool_call` followed by its `tool_result`).
  static AgentProgress fromMessages(
    List<ChatMessage> messages, {
    required bool live,
    DateTime? startedAt,
    String? heartbeatActivity,
    int? heartbeatElapsedSeconds,
    int? secondsSinceSignal,
    int? completedCount,
  }) {
    final byId = <String, AgentStep>{};
    final order = <String>[];

    for (final message in messages) {
      if (message.isToolCall) {
        final call = _firstToolCall(message);
        if (call == null) continue;
        final id = call['id']?.toString() ?? message.id;
        final name = call['name']?.toString() ?? 'tool';
        if (!byId.containsKey(id)) order.add(id);
        final execution = _stringMap(message.metadata?['tool_execution']);
        byId[id] = AgentStep(
          id: id,
          toolName: name,
          phase: phaseForTool(name),
          label: _labelFor(call, execution),
          started: execution?['status'] != null || byId.containsKey(id),
          // A tool_call with a result already folded in stays done; otherwise a
          // later tool_result message flips it. The backend's own "finished"
          // marker wins when present.
          done: byId[id]?.done ?? _executionStatus(execution) == 'finished',
          failed: byId[id]?.failed ?? _executionStatus(execution) == 'failed',
          durationMs:
              _intOrNull(execution?['duration_ms']) ?? byId[id]?.durationMs,
        );
        continue;
      }

      if (message.isToolResult) {
        final result = _toolResult(message);
        if (result == null) continue;
        final id = result['tool_call_id']?.toString();
        if (id == null) continue;
        final name = result['tool_name']?.toString() ?? 'tool';
        final isError = result['is_error'] == true;
        final existing = byId[id];
        final step =
            existing ??
            AgentStep(id: id, toolName: name, phase: phaseForTool(name));
        if (!order.contains(id)) order.add(id);
        byId[id] = step.copyWith(
          label: _resultLabel(result) ?? step.label,
          started: true,
          done: !isError,
          failed: isError,
          durationMs: _intOrNull(result['duration_ms']) ?? step.durationMs,
          resultPreview: _preview(result['result']),
        );
      }
    }

    return AgentProgress(
      steps: [for (final id in order) byId[id]!],
      live: live,
      startedAt: startedAt,
      heartbeatActivity: heartbeatActivity,
      heartbeatElapsedSeconds: heartbeatElapsedSeconds,
      secondsSinceSignal: secondsSinceSignal,
      completedCount: completedCount ?? byId.values.where((s) => s.done).length,
    );
  }

  /// Build progress from a workflow run's persisted `progress` entries.
  ///
  /// Used by the delegated-workflow tile. Entries are the same envelope the
  /// chat stream uses, replayed from the DB, so the semantics match.
  static AgentProgress fromWorkflowProgress(
    List<Map<String, dynamic>> entries, {
    required bool live,
    required bool failedRun,
    required bool cancelledRun,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? heartbeatActivity,
    int? heartbeatElapsedSeconds,
    int? secondsSinceSignal,
    int? completedCount,
  }) {
    final steps = <AgentStep>[];
    final indexById = <String, int>{};
    String? lastActivity;

    for (final entry in entries) {
      final type = entry['type']?.toString();
      if (type == 'heartbeat') {
        final beat = _stringMap(entry['metadata']?['heartbeat']);
        heartbeatActivity = beat?['activity']?.toString() ?? heartbeatActivity;
        final elapsed = _intOrNull(beat?['elapsed_s']);
        if (elapsed != null) heartbeatElapsedSeconds = elapsed;
        continue;
      }

      if (type == 'tool_execution') {
        final execution = _stringMap(entry['metadata']?['tool_execution']);
        final id = execution?['tool_call_id']?.toString();
        if (id == null) continue;
        final status = _executionStatus(execution);
        final label = execution?['title']?.toString();
        if (label != null && label.isNotEmpty) lastActivity = label;
        final existingIndex = indexById[id];
        if (existingIndex == null) {
          indexById[id] = steps.length;
          steps.add(
            AgentStep(
              id: id,
              toolName: execution?['tool_name']?.toString() ?? 'tool',
              phase: phaseForTool(execution?['tool_name']?.toString() ?? ''),
              label: label,
              durationMs: _intOrNull(execution?['duration_ms']),
              started: true,
              done: status == 'finished',
              failed: status == 'failed',
            ),
          );
        } else {
          steps[existingIndex] = steps[existingIndex].copyWith(
            label: label ?? steps[existingIndex].label,
            durationMs: _intOrNull(execution?['duration_ms']),
            started: true,
            done: status == 'finished' || steps[existingIndex].done,
            failed: status == 'failed',
          );
        }
        continue;
      }

      if (type == 'tool_call') {
        final calls = entry['tool_calls'];
        if (calls is! List || calls.isEmpty) continue;
        final call = _stringMap(calls.first);
        final id = call?['id']?.toString();
        if (id == null || indexById.containsKey(id)) continue;
        final name = call?['name']?.toString() ?? 'tool';
        indexById[id] = steps.length;
        steps.add(
          AgentStep(
            id: id,
            toolName: name,
            phase: phaseForTool(name),
            label: _labelFromArgs(_stringMap(call?['arguments'])),
            started: true,
          ),
        );
        continue;
      }

      if (type == 'tool_result') {
        final result = _stringMap(entry['tool_result']);
        final id =
            result?['tool_call_id']?.toString() ??
            entry['tool_call_id']?.toString();
        if (id == null) continue;
        final isError =
            result?['is_error'] == true || entry['is_error'] == true;
        final label = result?['title']?.toString();
        if (label != null && label.isNotEmpty) lastActivity = label;
        final index = indexById[id];
        if (index == null) continue;
        steps[index] = steps[index].copyWith(
          label: label ?? steps[index].label,
          durationMs:
              _intOrNull(result?['duration_ms']) ?? steps[index].durationMs,
          started: true,
          done: !isError,
          failed: isError,
          resultPreview: _preview(result?['result']),
        );
      }
    }

    // A run that ended is never "live", so its last step must not keep
    // spinning: mark the tail done (or failed) so the collapsed line settles.
    if (!live && steps.isNotEmpty) {
      final last = steps.length - 1;
      steps[last] = steps[last].copyWith(
        started: true,
        done: !failedRun && !cancelledRun && !steps[last].failed,
        failed: failedRun || steps[last].failed,
      );
    }

    return AgentProgress(
      steps: steps,
      live: live,
      startedAt: startedAt,
      finishedAt: finishedAt,
      heartbeatActivity: lastActivity ?? heartbeatActivity,
      heartbeatElapsedSeconds: heartbeatElapsedSeconds,
      secondsSinceSignal: secondsSinceSignal,
      completedCount: completedCount ?? steps.where((s) => s.done).length,
    );
  }

  /// Map a tool name onto the phase a user would recognize.
  ///
  /// Unknown tools fall back to [AgentProgressPhase.running] rather than being
  /// hidden: "the agent is doing something with `<tool>`" is still honest.
  static AgentProgressPhase phaseForTool(String name) {
    final n = name.trim().toLowerCase().replaceAll('-', '_');
    switch (n) {
      case 'read':
      case 'read_file':
        return AgentProgressPhase.reading;
      case 'edit':
      case 'write':
      case 'write_file':
      case 'patch':
      case 'apply_patch':
      case 'multiedit':
        return AgentProgressPhase.editing;
      case 'bash':
      case 'shell':
      case 'exec':
      case 'exec_command':
        return AgentProgressPhase.running;
      case 'grep':
      case 'glob':
      case 'list':
      case 'list_files':
      case 'search':
        return AgentProgressPhase.searching;
      case 'websearch':
      case 'web_search':
      case 'search_web':
      case 'webfetch':
      case 'web_fetch':
        return AgentProgressPhase.searching;
      case 'task':
      case 'micro_app':
        return AgentProgressPhase.building;
      case 'todowrite':
      case 'todoread':
        return AgentProgressPhase.thinking;
    }
    return AgentProgressPhase.running;
  }

  // -- helpers ---------------------------------------------------------------

  static Map<String, dynamic>? _firstToolCall(ChatMessage message) {
    final calls = message.metadata?['tool_calls'];
    if (calls is! List || calls.isEmpty || calls.first is! Map) return null;
    return _stringMap(calls.first);
  }

  static Map<String, dynamic>? _toolResult(ChatMessage message) {
    final nested = _stringMap(message.metadata?['tool_result']);
    if (nested != null) return nested;
    final meta = message.metadata;
    if (meta != null && meta.containsKey('tool_call_id')) return meta;
    return null;
  }

  /// Prefer the execution marker (backend-normalized), then the message's own
  /// metadata, then the call arguments.
  static String? _labelFor(
    Map<String, dynamic> call,
    Map<String, dynamic>? execution,
  ) {
    final fromExecution = execution?['title']?.toString();
    if (fromExecution != null && fromExecution.isNotEmpty) return fromExecution;
    return _labelFromArgs(_stringMap(call['arguments']));
  }

  static String? _resultLabel(Map<String, dynamic> result) {
    final title = result['title']?.toString();
    if (title != null && title.isNotEmpty) return title;
    return null;
  }

  /// Derive a label from raw tool arguments.
  ///
  /// Mirrors the backend's own preference order so a step reads the same
  /// whether it came from the live stream or a replayed timeline.
  static String? _labelFromArgs(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return null;
    const keys = [
      'command',
      'filePath',
      'path',
      'filename',
      'pattern',
      'query',
      'url',
    ];
    for (final key in keys) {
      final value = args[key];
      if (value is String && value.trim().isNotEmpty) {
        final text = value.trim();
        if (key == 'filePath' || key == 'path' || key == 'filename') {
          return _basename(text);
        }
        return text.length > 120 ? '${text.substring(0, 117)}…' : text;
      }
    }
    return null;
  }

  static String _basename(String value) {
    final normalized = value.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final parts = trimmed.split('/');
    return parts.isEmpty ? value : parts.last;
  }

  static String? _executionStatus(Map<String, dynamic>? execution) =>
      execution?['status']?.toString();

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _preview(Object? result) {
    if (result == null) return null;
    if (result is String) {
      final flat = result.replaceAll(RegExp(r'\s+'), ' ').trim();
      return flat.isEmpty
          ? null
          : (flat.length > 120 ? '${flat.substring(0, 117)}…' : flat);
    }
    if (result is Map) {
      for (final key in ['summary', 'error', 'message', 'output']) {
        final value = result[key];
        if (value is String && value.trim().isNotEmpty) {
          final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
          return flat.length > 120 ? '${flat.substring(0, 117)}…' : flat;
        }
      }
    }
    return null;
  }

  static Map<String, dynamic>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
