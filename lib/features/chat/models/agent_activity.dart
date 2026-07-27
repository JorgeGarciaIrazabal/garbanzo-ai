import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

enum AgentActivityKind {
  prepareApp,
  research,
  gatherData,
  exploreFiles,
  reviewFile,
  updateFile,
  checkApp,
  runStep,
  useTool,
}

class AgentActivityStep {
  const AgentActivityStep({
    required this.callId,
    required this.kind,
    required this.toolName,
    this.target,
    this.done = false,
    this.failed = false,
  });

  final String callId;
  final AgentActivityKind kind;
  final String toolName;
  final String? target;
  final bool done;
  final bool failed;

  factory AgentActivityStep.fromToolCall(
    Map call, {
    bool done = false,
    bool failed = false,
  }) {
    final data = _stringMap(call);
    final name = data['name']?.toString() ?? 'tool';
    final args = _stringMap(data['arguments']);
    return AgentActivityStep(
      callId: data['id']?.toString() ?? name,
      kind: _kindFor(name, args),
      toolName: name,
      target: _targetFor(args),
      done: done,
      failed: failed,
    );
  }
}

/// Converts raw tool call/result messages into grounded, displayable steps.
class AgentActivityGroup {
  const AgentActivityGroup({
    required this.messages,
    required this.steps,
    required this.isMicroApp,
    required this.isEditing,
    this.appName,
    this.microAppFailed = false,
  });

  factory AgentActivityGroup.fromMessages(List<ChatMessage> messages) {
    final results = <String, Map<String, dynamic>>{};
    for (final message in messages.where((message) => message.isToolResult)) {
      final data = _toolResult(message);
      final id = data?['tool_call_id'];
      if (id is String) results[id] = data!;
    }

    var isMicroApp = false;
    var isEditing = false;
    var microAppFailed = false;
    String? appName;
    final steps = <AgentActivityStep>[];

    for (final message in messages.where((message) => message.isToolCall)) {
      final call = _toolCall(message);
      if (call == null) continue;
      final id = call['id']?.toString() ?? message.id;
      final name = call['name']?.toString() ?? message.content;
      final args = _stringMap(call['arguments']);
      final result = results[id];

      if (_normalized(name) == 'micro_app') {
        isMicroApp = true;
        isEditing = args['edit'] != false;
        final resultValue = result?['result'];
        final resultApp = resultValue is Map ? resultValue['app'] : null;
        appName = humanize(
          args['app']?.toString() ?? resultApp?.toString() ?? 'micro-app',
        );
        microAppFailed = _resultFailed(result);
        continue;
      }

      steps.add(
        AgentActivityStep.fromToolCall(
          call,
          done: result != null,
          failed: _resultFailed(result),
        ),
      );
    }

    return AgentActivityGroup(
      messages: messages,
      steps: steps,
      isMicroApp: isMicroApp,
      isEditing: isEditing,
      appName: appName,
      microAppFailed: microAppFailed,
    );
  }

  final List<ChatMessage> messages;
  final List<AgentActivityStep> steps;
  final bool isMicroApp;
  final bool isEditing;
  final String? appName;
  final bool microAppFailed;

  AgentActivityStep get fallbackStep => AgentActivityStep(
    callId: 'preparing',
    kind: isMicroApp ? AgentActivityKind.prepareApp : AgentActivityKind.runStep,
    toolName: isMicroApp ? 'micro_app' : 'tool',
    target: appName,
  );

  AgentActivityStep? get currentStep {
    if (steps.isNotEmpty) return steps.last;
    return isMicroApp ? fallbackStep : null;
  }
}

Map<String, dynamic>? _toolCall(ChatMessage message) {
  final calls = message.metadata?['tool_calls'];
  if (calls is! List || calls.isEmpty || calls.first is! Map) return null;
  return _stringMap(calls.first);
}

Map<String, dynamic>? _toolResult(ChatMessage message) {
  final nested = message.metadata?['tool_result'];
  if (nested is Map) return _stringMap(nested);
  final metadata = message.metadata;
  if (metadata != null && metadata.containsKey('tool_call_id')) return metadata;
  return null;
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

bool _resultFailed(Map<String, dynamic>? result) {
  if (result == null) return false;
  if (result['is_error'] == true) return true;
  final value = result['result'];
  return value is Map && (value['ok'] == false || value['is_error'] == true);
}

AgentActivityKind _kindFor(String name, Map<String, dynamic> args) {
  final normalized = _normalized(name);
  if (const ['websearch', 'web_search', 'search_web'].contains(normalized)) {
    return AgentActivityKind.research;
  }
  if (const ['webfetch', 'web_fetch', 'fetch'].contains(normalized)) {
    return AgentActivityKind.gatherData;
  }
  if (const [
    'glob',
    'grep',
    'list',
    'list_files',
    'search',
  ].contains(normalized)) {
    return AgentActivityKind.exploreFiles;
  }
  if (const ['read', 'read_file'].contains(normalized)) {
    return AgentActivityKind.reviewFile;
  }
  if (const [
    'edit',
    'write',
    'write_file',
    'patch',
    'apply_patch',
    'multiedit',
  ].contains(normalized)) {
    return AgentActivityKind.updateFile;
  }
  if (const ['bash', 'shell', 'exec', 'exec_command'].contains(normalized)) {
    final command = (args['command'] ?? args['cmd'] ?? '')
        .toString()
        .toLowerCase();
    if (RegExp(
      r'\b(test|lint|check|build|validate|analy[sz]e)\b',
    ).hasMatch(command)) {
      return AgentActivityKind.checkApp;
    }
    return AgentActivityKind.runStep;
  }
  return AgentActivityKind.useTool;
}

String? _targetFor(Map<String, dynamic> args) {
  final path =
      args['filePath'] ??
      args['file_path'] ??
      args['path'] ??
      args['filename'] ??
      args['file'];
  if (path is! String || path.trim().isEmpty) return null;
  return path.replaceAll('\\', '/').split('/').last;
}

String _normalized(String value) =>
    value.trim().toLowerCase().replaceAll('-', '_');

String humanize(String value) {
  final words = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return value;
  final text = words.join(' ');
  return '${text[0].toUpperCase()}${text.substring(1)}';
}
