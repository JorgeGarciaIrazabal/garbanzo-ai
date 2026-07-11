import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart'
    show parseSseChunks;
import 'package:garbanzo_ai/features/microapps/models/micro_app.dart';

/// The micro-apps backend surface the provider depends on. An interface so
/// tests can supply a fake without the HTTP client.
abstract class MicroappApi {
  Future<WorkspaceStatus> startWorkspace();
  Future<WorkspaceStatus> getWorkspace();
  Future<WorkspaceStatus> stopWorkspace();
  Future<List<MicroAppInfo>> listApps();
  Future<List<HouseFile>> listHouses();
  Future<HouseFile> createHouse(String name, {String? template});
  Future<ChangesSummary> getChanges();
  Future<PublishResult> publish({String? message});
  Future<ChangesSummary> revert({List<String>? paths, bool all});
  Stream<ChatResponseChunk> streamAgentChat({
    required String instruction,
    String? sessionId,
  });
  Future<bool> abortAgent(String sessionId);
  String? appUrl(WorkspaceStatus ws, MicroAppInfo app, {HouseFile? house});
}

/// REST + SSE client for the `/api/v1/microapps/*` backend.
///
/// The agent chat reuses the main chat's SSE envelope ([ChatResponseChunk])
/// and [parseSseChunks], so agent narration renders with the same widgets.
class MicroappService implements MicroappApi {
  MicroappService._();
  static final MicroappService instance = MicroappService._();

  final _client = ApiClient.instance;

  /// Host part of the API base URL (scheme://host[:port]) — used to compose a
  /// dev-server URL reachable from THIS device (e.g. an Android phone), since
  /// the backend's `dev_url` is loopback-only.
  Uri get _apiBase => Uri.parse(_client.baseUrl);

  // ---- workspace lifecycle ------------------------------------------------

  @override
  Future<WorkspaceStatus> startWorkspace() =>
      _statusFrom(_client.post('/api/v1/microapps/workspace'));

  @override
  Future<WorkspaceStatus> getWorkspace() =>
      _statusFrom(_client.get('/api/v1/microapps/workspace'));

  @override
  Future<WorkspaceStatus> stopWorkspace() =>
      _statusFrom(_client.delete('/api/v1/microapps/workspace'));

  Future<WorkspaceStatus> _statusFrom(Future<Response> req) async {
    final res = await req;
    _ensureOk(res);
    return WorkspaceStatus.fromJson(res.data as Map<String, dynamic>);
  }

  // ---- apps + houses ------------------------------------------------------

  @override
  Future<List<MicroAppInfo>> listApps() async {
    final res = await _client.get('/api/v1/microapps/apps');
    _ensureOk(res);
    return (res.data as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(MicroAppInfo.fromJson)
        .toList();
  }

  @override
  Future<List<HouseFile>> listHouses() async {
    final res = await _client.get('/api/v1/microapps/houses');
    _ensureOk(res);
    return (res.data as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(HouseFile.fromJson)
        .toList();
  }

  @override
  Future<HouseFile> createHouse(String name, {String? template}) async {
    final res = await _client.post(
      '/api/v1/microapps/houses',
      data: {'name': name, 'template': ?template},
    );
    _ensureOk(res, expected: {200, 201});
    return HouseFile.fromJson(res.data as Map<String, dynamic>);
  }

  // ---- changes / publish / revert -----------------------------------------

  @override
  Future<ChangesSummary> getChanges() async {
    final res = await _client.get('/api/v1/microapps/changes');
    _ensureOk(res);
    return ChangesSummary.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<PublishResult> publish({String? message}) async {
    final res = await _client.post(
      '/api/v1/microapps/publish',
      data: {'message': ?message},
    );
    _ensureOk(res);
    return PublishResult.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<ChangesSummary> revert({List<String>? paths, bool all = false}) async {
    final res = await _client.post(
      '/api/v1/microapps/revert',
      data: {'paths': ?paths, 'all': all},
    );
    _ensureOk(res);
    return ChangesSummary.fromJson(res.data as Map<String, dynamic>);
  }

  // ---- agent SSE ----------------------------------------------------------

  /// Stream an instruction to the opencode agent. Emits [ChatResponseChunk]s:
  /// `session` (first, metadata.session_id) → `chunk`/`thinking`/`tool_*` →
  /// `done`/`error`.
  @override
  Stream<ChatResponseChunk> streamAgentChat({
    required String instruction,
    String? sessionId,
  }) async* {
    final res = await _client.streamPost(
      '/api/v1/microapps/agent/chat',
      data: {'instruction': instruction, 'session_id': ?sessionId},
    );
    final body = res.data as ResponseBody;
    if (res.statusCode != 200) {
      final err = await body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      throw Exception('Agent chat failed: ${res.statusCode} - $err');
    }
    yield* parseSseChunks(
      body.stream.cast<List<int>>().transform(utf8.decoder),
    );
  }

  @override
  Future<bool> abortAgent(String sessionId) async {
    final res = await _client.post(
      '/api/v1/microapps/agent/abort',
      data: {'session_id': sessionId},
    );
    _ensureOk(res);
    final data = res.data;
    return data is Map<String, dynamic> && (data['aborted'] as bool? ?? false);
  }

  // ---- URL composition ----------------------------------------------------

  /// Build the URL to display an app, reachable from THIS device.
  ///
  /// Proxied workspaces (deployments) load through the backend's /micro-apps
  /// reverse proxy on the API origin, authenticated by a panel token.
  /// Otherwise prefers composing `<api-host>:<devPort>` (works from a phone)
  /// and falls back to the backend's loopback `devUrl` (same-host
  /// web/desktop).
  @override
  String? appUrl(WorkspaceStatus ws, MicroAppInfo app, {HouseFile? house}) {
    final query = <String>[];
    if (app.isAiEnabled && house != null) {
      query
        ..add('embed=1')
        ..add('project=/micro-apps/${house.path}')
        ..add('save=1');
    }
    if (ws.proxied) {
      if (ws.panelToken != null) query.add('mp_token=${ws.panelToken}');
      final qs = query.isEmpty ? '' : '?${query.join('&')}';
      return '${proxyOrigin()}/micro-apps/${app.path}$qs';
    }
    final origin = _devOrigin(ws);
    if (origin == null) return null;
    final qs = query.isEmpty ? '' : '?${query.join('&')}';
    return '$origin/micro-apps/${app.path}$qs';
  }

  /// The backend origin the /micro-apps proxy lives on. Empty API base (web
  /// release served by the backend itself) → relative URL on the page origin.
  static String proxyOrigin() {
    final base = ApiClient.instance.baseUrl;
    if (base.isEmpty) return '';
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  /// The dev-server origin reachable from this device.
  String? _devOrigin(WorkspaceStatus ws) {
    if (ws.devPort != null) {
      final host = _apiBase.host;
      if (host.isNotEmpty && host != '127.0.0.1' && host != 'localhost') {
        return '${_apiBase.scheme}://$host:${ws.devPort}';
      }
    }
    return ws.devUrl; // loopback fallback (same-host web/desktop)
  }

  void _ensureOk(Response res, {Set<int> expected = const {200}}) {
    if (!expected.contains(res.statusCode)) {
      final data = res.data;
      final detail = data is Map<String, dynamic>
          ? (data['detail'] as String? ?? '$data')
          : '$data';
      throw MicroappApiException(res.statusCode ?? 0, detail);
    }
  }
}

/// A typed API error carrying the HTTP status (404 = feature disabled, 409 =
/// business error such as an invalid house or a rebase conflict).
class MicroappApiException implements Exception {
  final int statusCode;
  final String detail;
  const MicroappApiException(this.statusCode, this.detail);

  bool get isFeatureDisabled => statusCode == 404;

  @override
  String toString() => 'MicroappApiException($statusCode): $detail';
}
