/// Data models for the Micro-Apps Agentic Workspace feature.
///
/// Plain hand-written classes (matching `features/usage`), mapping the backend
/// `/api/v1/microapps/*` JSON contract. The backend hosts a git worktree of the
/// user's micro-apps repo, runs its dev server + an opencode agent, and streams
/// agent edits back over SSE.
library;

/// Live status of the user's workspace (worktree + dev server + opencode).
class WorkspaceStatus {
  final String state; // stopped | starting | ready | error
  final String? devUrl; // loopback URL — same-host only
  final int? devPort; // port; compose with API host for other devices
  final String? branch;
  final bool opencodeReady;
  final String? setupProgress;

  const WorkspaceStatus({
    required this.state,
    this.devUrl,
    this.devPort,
    this.branch,
    this.opencodeReady = false,
    this.setupProgress,
  });

  bool get isReady => state == 'ready' && opencodeReady;
  bool get isBusy => state == 'starting';
  bool get isStopped => state == 'stopped';

  factory WorkspaceStatus.fromJson(Map<String, dynamic> json) => WorkspaceStatus(
        state: json['state'] as String? ?? 'stopped',
        devUrl: json['dev_url'] as String?,
        devPort: (json['dev_port'] as num?)?.toInt(),
        branch: json['branch'] as String?,
        opencodeReady: json['opencode_ready'] as bool? ?? false,
        setupProgress: json['setup_progress'] as String?,
      );
}

/// A registry.json entry describing an embeddable micro-app.
class MicroAppInfo {
  final String id;
  final String name;
  final String path; // deploy path, e.g. "house-designer/"
  final String? icon;
  final String? description;
  final bool projectParam; // accepts ?project=<file>
  final String? dataDir; // e.g. "houses/"
  final String? dataExt; // e.g. ".house.json"
  final List<String> suggestions;

  const MicroAppInfo({
    required this.id,
    required this.name,
    required this.path,
    this.icon,
    this.description,
    this.projectParam = false,
    this.dataDir,
    this.dataExt,
    this.suggestions = const [],
  });

  /// Whether this app is agent-editable (has a data dir + project param).
  bool get isAiEnabled => projectParam && dataDir != null;

  factory MicroAppInfo.fromJson(Map<String, dynamic> json) => MicroAppInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? (json['id'] as String? ?? 'App'),
        path: json['path'] as String? ?? '',
        icon: json['icon'] as String?,
        description: json['description'] as String?,
        projectParam: json['projectParam'] as bool? ?? false,
        dataDir: json['dataDir'] as String?,
        dataExt: json['dataExt'] as String?,
        suggestions: (json['suggestions'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
      );
}

/// A data file in the app's data dir (e.g. a `houses/*.house.json`).
class HouseFile {
  final String path; // repo-relative
  final String name;
  final double modifiedAt;
  final int size;

  const HouseFile({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.size,
  });

  factory HouseFile.fromJson(Map<String, dynamic> json) => HouseFile(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '',
        modifiedAt: (json['modified_at'] as num?)?.toDouble() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// One changed file in the workspace vs the publish base.
class ChangeFile {
  final String path;
  final String status; // M A D R ? U
  final int plus;
  final int minus;

  const ChangeFile({
    required this.path,
    required this.status,
    this.plus = 0,
    this.minus = 0,
  });

  factory ChangeFile.fromJson(Map<String, dynamic> json) => ChangeFile(
        path: json['path'] as String? ?? '',
        status: json['status'] as String? ?? '?',
        plus: (json['plus'] as num?)?.toInt() ?? 0,
        minus: (json['minus'] as num?)?.toInt() ?? 0,
      );
}

/// Summary of uncommitted + committed changes vs origin/main.
class ChangesSummary {
  final List<ChangeFile> files;
  final int ahead;
  final int behind;

  const ChangesSummary({
    this.files = const [],
    this.ahead = 0,
    this.behind = 0,
  });

  bool get hasChanges => files.isNotEmpty || ahead > 0;

  factory ChangesSummary.fromJson(Map<String, dynamic> json) => ChangesSummary(
        files: (json['files'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ChangeFile.fromJson)
            .toList(),
        ahead: (json['ahead'] as num?)?.toInt() ?? 0,
        behind: (json['behind'] as num?)?.toInt() ?? 0,
      );
}

/// Outcome of a publish operation.
class PublishResult {
  final bool committed;
  final String? commit;
  final bool pushed;
  final String message;

  const PublishResult({
    required this.committed,
    this.commit,
    required this.pushed,
    required this.message,
  });

  factory PublishResult.fromJson(Map<String, dynamic> json) => PublishResult(
        committed: json['committed'] as bool? ?? false,
        commit: json['commit'] as String?,
        pushed: json['pushed'] as bool? ?? false,
        message: json['message'] as String? ?? '',
      );
}

/// Status of a single natural-language instruction sent to the agent.
enum InstructionStatus { pending, streaming, applied, failed }

/// A row in the workspace's instruction history.
class InstructionEntry {
  final String instruction;
  InstructionStatus status;
  String summary; // accumulated assistant narration
  String? error;

  InstructionEntry({
    required this.instruction,
    this.status = InstructionStatus.pending,
    this.summary = '',
    this.error,
  });
}
