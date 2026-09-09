import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';
import 'package:uuid/uuid.dart';

const _kUnavailable = 'Topics are temporarily unavailable';
const _kLimited = 'Historical context is temporarily limited';

class TopicDiscoveryProvider extends ChangeNotifier {
  TopicDiscoveryProvider({TopicService? service})
    : _service = service ?? TopicService.instance;

  final TopicService _service;
  final Map<TopicOrigin, List<TopicNode>> _trees = {};

  TopicOrigin _mode = TopicOrigin.personal;
  TopicOrigin get mode => _mode;
  List<TopicNode> get topics => List.unmodifiable(_trees[_mode] ?? const []);

  List<TopicNode> _path = const [];
  List<TopicNode> get path => List.unmodifiable(_path);

  TopicNode? _selectedTopic;
  TopicNode? get selectedTopic => _selectedTopic;

  TopicDriftProposal? _pendingDrift;
  TopicDriftProposal? get pendingDrift => _pendingDrift;

  Future<void> Function(TopicSwitchResponse response)? onTopicSwitched;
  Future<void> Function(TopicSwitchResponse response)? onTopicCombined;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _showLanding = true;
  bool get showLanding => _showLanding;

  final Set<TopicOrigin> _loadingModes = {};
  bool get loading => _loadingModes.contains(_mode);

  String? _error;
  String? get error => _error;

  int _promotedCount = 4;
  int get promotedCount => _promotedCount;

  final Map<String, List<TopicArchive>> _topicArchives = {};
  Map<String, List<TopicArchive>> get topicArchives =>
      Map.unmodifiable(_topicArchives);
  final Set<String> _loadingArchiveTopics = {};
  bool isArchiveListLoading(String topicId) =>
      _loadingArchiveTopics.contains(topicId);
  final Map<String, String> _archiveListErrors = {};
  String? archiveListError(String topicId) => _archiveListErrors[topicId];
  final Map<String, TopicArchivePage> _archivePages = {};
  TopicArchivePage? archivePage(String archiveId) => _archivePages[archiveId];
  final Set<String> _loadingArchiveIds = {};
  bool isArchiveLoading(String archiveId) =>
      _loadingArchiveIds.contains(archiveId);
  final Map<String, String> _archiveErrors = {};
  String? archiveError(String archiveId) => _archiveErrors[archiveId];

  TopicContextStatus get contextStatus =>
      _selectedTopic?.contextStatus ?? TopicContextStatus.empty;

  List<ActiveContextItem> _retainedItems = const [];
  List<ActiveContextItem> get retainedItems =>
      List.unmodifiable(_retainedItems);

  String? _lastSwitchIdempotencyKey;
  String? get lastSwitchIdempotencyKey => _lastSwitchIdempotencyKey;
  final Map<String, String> _pendingSwitchKeys = {};

  void setPromotedCount(int count) {
    final next = count.clamp(1, 4);
    if (_promotedCount == next) return;
    _promotedCount = next;
    notifyListeners();
  }

  Future<void> load({bool force = false}) async {
    final requestedMode = _mode;
    if (_loadingModes.contains(requestedMode) ||
        (!force && _trees.containsKey(requestedMode))) {
      return;
    }
    _loadingModes.add(requestedMode);
    _error = null;
    notifyListeners();
    try {
      _trees[requestedMode] = await _service.listTopics(requestedMode);
    } catch (e) {
      _error = _kUnavailable;
      logDebug('Failed to load topics: $e');
    } finally {
      _loadingModes.remove(requestedMode);
      notifyListeners();
    }
  }

  Future<void> loadArchives(String topicId) async {
    if (_loadingArchiveTopics.contains(topicId)) return;
    _loadingArchiveTopics.add(topicId);
    _archiveListErrors.remove(topicId);
    notifyListeners();
    try {
      _topicArchives[topicId] = await _service.listArchives(topicId);
    } catch (e) {
      _archiveListErrors[topicId] = 'Could not load earlier sessions';
      logDebug('Failed to load topic archives: $e');
    } finally {
      _loadingArchiveTopics.remove(topicId);
      notifyListeners();
    }
  }

  Future<void> loadArchivePage(
    String topicId,
    String archiveId, {
    bool older = false,
  }) async {
    if (_loadingArchiveIds.contains(archiveId)) return;
    final current = _archivePages[archiveId];
    if (!older && current != null) return;
    if (older && (current == null || !current.hasMore)) return;
    _loadingArchiveIds.add(archiveId);
    _archiveErrors.remove(archiveId);
    notifyListeners();
    try {
      final page = await _service.getArchivePage(
        topicId,
        archiveId,
        before: older && current!.messages.isNotEmpty
            ? current.messages.first.id
            : null,
      );
      _archivePages[archiveId] = older && current != null
          ? current.prepend(page)
          : page;
    } catch (e) {
      _archiveErrors[archiveId] = 'Could not load this earlier session';
      logDebug('Failed to load topic archive $archiveId: $e');
    } finally {
      _loadingArchiveIds.remove(archiveId);
      notifyListeners();
    }
  }

  Future<TopicSwitchResponse> switchTopic(
    String conversationId, {
    String? topicId,
    String? label,
    bool archive = true,
    bool retainPinned = true,
    String? idempotencyKey,
    String mode = 'switch',
  }) async {
    _error = null;
    final signature = _switchSignature(
      topicId,
      label,
      mode,
      archive: archive,
      retainPinned: retainPinned,
    );
    final actionKey =
        idempotencyKey ??
        _pendingSwitchKeys.putIfAbsent(signature, () => const Uuid().v4());
    final r = await _service.switchTopic(
      conversationId,
      topicId: topicId,
      label: label,
      archive: archive,
      retainPinned: retainPinned,
      idempotencyKey: actionKey,
      mode: mode,
    );
    _applySwitchResponse(r, origin: _originForTopic(topicId));
    _pendingSwitchKeys.remove(signature);
    _lastSwitchIdempotencyKey = r.idempotencyKey;
    if (mode == 'combine') {
      final combined = onTopicCombined;
      if (combined != null) await combined(r);
    } else {
      final switched = onTopicSwitched;
      if (switched != null) await switched(r);
    }
    notifyListeners();
    return r;
  }

  Future<TopicSwitchResponse> combineTopics(
    String conversationId, {
    String? topicId,
    String? label,
    String? idempotencyKey,
  }) async {
    return switchTopic(
      conversationId,
      topicId: topicId,
      label: label,
      archive: false,
      idempotencyKey: idempotencyKey,
      mode: 'combine',
    );
  }

  Future<void> setMode(TopicOrigin mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _path = const [];
    notifyListeners();
    await load();
  }

  void openChildren(TopicNode topic) {
    if (topic.children.isEmpty && topic.childCount == 0) return;
    _path = [..._path, topic];
    notifyListeners();
  }

  void goToPathIndex(int index) {
    _path = index < 0 ? const [] : _path.take(index + 1).toList();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  List<TopicNode> get visibleTopics {
    var cur = topics;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      return _matchingTopics(topics, q);
    }
    for (final crumb in _path) {
      final refreshed = cur.where((n) => n.id == crumb.id).firstOrNull;
      if (refreshed == null) return const [];
      cur = refreshed.children;
    }
    return cur;
  }

  Future<void> activate(String conversationId, TopicNode topic) async {
    _selectedTopic =
        topic.origin != TopicOrigin.suggested &&
            topic.contextStatus != TopicContextStatus.ready
        ? topic.copyWith(contextStatus: TopicContextStatus.preparing)
        : topic;
    _showLanding = false;
    _error = null;
    notifyListeners();
    final signature = _switchSignature(
      topic.id,
      null,
      'switch',
      archive: true,
      retainPinned: true,
    );
    final actionKey = _pendingSwitchKeys.putIfAbsent(
      signature,
      () => const Uuid().v4(),
    );
    try {
      final res = await _service.switchTopic(
        conversationId,
        topicId: topic.id,
        idempotencyKey: actionKey,
      );
      _applySwitchResponse(res, origin: topic.origin);
      _pendingSwitchKeys.remove(signature);
      _lastSwitchIdempotencyKey = res.idempotencyKey;
      final switched = onTopicSwitched;
      if (switched != null) await switched(res);
    } catch (e) {
      _selectedTopic = topic.copyWith(
        contextStatus: TopicContextStatus.limited,
      );
      _error = _kLimited;
      logDebug('Failed to activate topic: $e');
      notifyListeners();
    }
  }

  Future<void> activateFreeText(String conversationId, String label) async {
    final requestedOrigin = _mode;
    final topic = TopicNode(
      id: 'provisional-${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      origin: requestedOrigin,
      contextStatus: TopicContextStatus.preparing,
    );
    _selectedTopic = topic;
    _showLanding = false;
    notifyListeners();
    final signature = _switchSignature(
      null,
      label,
      'switch',
      archive: true,
      retainPinned: true,
    );
    final actionKey = _pendingSwitchKeys.putIfAbsent(
      signature,
      () => const Uuid().v4(),
    );
    try {
      final response = await _service.switchTopic(
        conversationId,
        label: label,
        idempotencyKey: actionKey,
      );
      _applySwitchResponse(response, origin: requestedOrigin);
      _pendingSwitchKeys.remove(signature);
      _lastSwitchIdempotencyKey = response.idempotencyKey;
      final switched = onTopicSwitched;
      if (switched != null) await switched(response);
    } catch (_) {
      _selectedTopic = topic.copyWith(
        contextStatus: TopicContextStatus.limited,
      );
      _error = _kLimited;
      notifyListeners();
    }
  }

  void startNewTopic() {
    _selectedTopic = null;
    _pendingDrift = null;
    _path = const [];
    _showLanding = true;
    _error = null;
    notifyListeners();
    unawaited(load());
  }

  /// Reconciles server-owned selection data while preserving the current view.
  void synchronizeSelectedTopic(TopicNode? topic) {
    if (_selectedTopic == topic) return;
    _selectedTopic = topic;
    notifyListeners();
  }

  void setSelectedTopic(TopicNode? topic) {
    _selectedTopic = topic;
    if (topic != null) {
      _showLanding = false;
    }
    notifyListeners();
  }

  void conversationStarted() {
    if (!_showLanding) return;
    _showLanding = false;
    notifyListeners();
  }

  void applyTopicUpdate(Map<String, dynamic> payload) {
    final raw = payload['topic'] ?? payload;
    if (raw is! Map<String, dynamic>) return;
    final changed = TopicNode.fromJson(raw);
    final cacheMode = changed.origin == TopicOrigin.suggested
        ? TopicOrigin.explore
        : TopicOrigin.personal;
    final roots = _trees[cacheMode] ?? const [];
    _trees[cacheMode] = _containsNode(roots, changed.id)
        ? _replaceNode(roots, changed)
        : changed.parentId == null
        ? [...roots, changed]
        : roots;
    if (_mode == cacheMode) {
      _path = _path
          .map((c) => _findNode(_trees[cacheMode]!, c.id) ?? c)
          .toList(growable: false);
    }
    if (_selectedTopic?.id == changed.id) _selectedTopic = changed;
    notifyListeners();
  }

  void applyPreparing(Map<String, dynamic> payload) {
    final s = _selectedTopic;
    if (s == null) return;
    _selectedTopic = s.copyWith(
      contextStatus: payload['limited'] == true
          ? TopicContextStatus.limited
          : TopicContextStatus.preparing,
    );
    notifyListeners();
  }

  void applyTopicDrift(Map<String, dynamic> payload) {
    final raw = payload['topic_drift'] ?? payload;
    if (raw is! Map<String, dynamic>) return;
    _pendingDrift = TopicDriftProposal.fromJson(raw);
    notifyListeners();
  }

  void dismissDrift() {
    _pendingDrift = null;
    notifyListeners();
  }

  Future<TopicSwitchResponse?> acceptDrift(
    String conversationId, {
    String mode = 'switch',
  }) async {
    final drift = _pendingDrift;
    if (drift == null) return null;
    _pendingDrift = null;
    return switchTopic(
      conversationId,
      topicId: drift.detectedTopicId,
      mode: mode,
    );
  }

  List<TopicNode> _replaceNode(List<TopicNode> nodes, TopicNode changed) =>
      nodes
          .map(
            (n) => n.id == changed.id
                ? changed
                : _containsNode(n.children, changed.id)
                ? n.copyWith(children: _replaceNode(n.children, changed))
                : n,
          )
          .toList(growable: false);

  bool _containsNode(List<TopicNode> nodes, String id) =>
      nodes.any((n) => n.id == id || _containsNode(n.children, id));

  TopicNode? _findNode(List<TopicNode> nodes, String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
      final child = _findNode(n.children, id);
      if (child != null) return child;
    }
    return null;
  }

  void _applySwitchResponse(
    TopicSwitchResponse response, {
    required TopicOrigin origin,
  }) {
    final topic = response.topic;
    if (topic == null) {
      throw StateError('Topic switch response did not include a topic');
    }
    _selectedTopic = TopicNode(
      id: topic.id,
      label: topic.label,
      parentId: topic.parentId,
      parentLabel: topic.parentLabel,
      description: topic.description,
      origin: origin,
      score: 1,
      childCount: 0,
      contextStatus: response.contextStatus,
      combinedTopics: topic.combinedTopics,
    );
    _retainedItems = response.retainedItems;
    _pendingDrift = null;
    _showLanding = false;
  }

  TopicOrigin _originForTopic(String? topicId) {
    if (topicId == null) return _mode;
    for (final roots in _trees.values) {
      final node = _findNode(roots, topicId);
      if (node != null) return node.origin;
    }
    return _mode;
  }

  List<TopicNode> _matchingTopics(List<TopicNode> nodes, String query) {
    final matches = <TopicNode>[];

    void visit(TopicNode node, List<String> ancestorLabels) {
      final path = [...ancestorLabels, node.label];
      if (node.label.toLowerCase().contains(query)) {
        matches.add(
          node.copyWith(
            parentLabel: ancestorLabels.isEmpty
                ? node.parentLabel
                : ancestorLabels.join(' › '),
          ),
        );
      }
      for (final child in node.children) {
        visit(child, path);
      }
    }

    for (final node in nodes) {
      visit(node, const []);
    }
    return matches;
  }

  String _switchSignature(
    String? topicId,
    String? label,
    String mode, {
    required bool archive,
    required bool retainPinned,
  }) =>
      '$mode:$archive:$retainPinned:${topicId ?? ''}:${label?.trim().toLowerCase() ?? ''}';
}
