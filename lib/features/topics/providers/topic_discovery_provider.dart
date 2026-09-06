import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';

const _kUnavailable = 'Topics are temporarily unavailable';
const _kLimited = 'Historical context is temporarily limited';
const _presentationTopicPrefix = 'presentation:';

class TopicDiscoveryProvider extends ChangeNotifier {
  TopicDiscoveryProvider({TopicService? service})
    : _service = service ?? TopicService.instance;

  final TopicService _service;
  final Map<TopicOrigin, List<TopicNode>> _trees = {};

  TopicOrigin _mode = TopicOrigin.personal;
  TopicOrigin get mode => _mode;
  List<TopicNode> get topics =>
      List.unmodifiable(_presentationHierarchy(_trees[_mode] ?? const []));

  List<TopicNode> _path = const [];
  List<TopicNode> get path => List.unmodifiable(_path);

  TopicNode? _selectedTopic;
  TopicNode? get selectedTopic => _selectedTopic;

  TopicDriftProposal? _pendingDrift;
  TopicDriftProposal? get pendingDrift => _pendingDrift;

  VoidCallback? onTopicSwitched;
  VoidCallback? onTopicCombined;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _showLanding = true;
  bool get showLanding => _showLanding;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  int _promotedCount = 4;
  int get promotedCount => _promotedCount;

  final Map<String, List<TopicArchive>> _topicArchives = {};
  Map<String, List<TopicArchive>> get topicArchives =>
      Map.unmodifiable(_topicArchives);

  TopicContextStatus get contextStatus =>
      _selectedTopic?.contextStatus ?? TopicContextStatus.empty;

  void setPromotedCount(int count) {
    final next = count.clamp(1, 4);
    if (_promotedCount == next) return;
    _promotedCount = next;
    notifyListeners();
  }

  Future<void> load({bool force = false}) async {
    if (_loading || (!force && _trees.containsKey(_mode))) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _trees[_mode] = await _service.listTopics(_mode);
    } catch (e) {
      _error = _kUnavailable;
      logDebug('Failed to load topics: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadArchives(String topicId) async {
    try {
      _topicArchives[topicId] = await _service.listArchives(topicId);
      notifyListeners();
    } catch (e) {
      logDebug('Failed to load topic archives: $e');
    }
  }

  Future<TopicSwitchResponse> switchTopic(
    String conversationId, {
    String? topicId,
    String? label,
    bool archive = true,
    int carryoverMaxItems = 5,
    int carryoverMaxTokens = 400,
    String mode = 'switch',
  }) async {
    _error = null;
    final r = await _service.switchTopic(
      conversationId,
      topicId: topicId,
      label: label,
      archive: archive,
      carryoverMaxItems: carryoverMaxItems,
      carryoverMaxTokens: carryoverMaxTokens,
      mode: mode,
    );
    if (r.topic != null) {
      _selectedTopic = TopicNode(
        id: r.topic!.id,
        label: r.topic!.label,
        parentId: r.topic!.parentId,
        parentLabel: r.topic!.parentLabel,
        description: r.topic!.description,
        origin: TopicOrigin.history,
        score: 1,
        childCount: 0,
        contextStatus: TopicContextStatus.ready,
        combinedTopics: r.topic!.combinedTopics,
      );
      _showLanding = false;
    }
    if (mode == 'combine') {
      onTopicCombined?.call();
    } else {
      onTopicSwitched?.call();
    }
    notifyListeners();
    return r;
  }

  Future<TopicSwitchResponse> combineTopics(
    String conversationId, {
    String? topicId,
    String? label,
  }) async {
    return switchTopic(
      conversationId,
      topicId: topicId,
      label: label,
      archive: false,
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
    for (final crumb in _path) {
      if (crumb.id.startsWith(_presentationTopicPrefix)) {
        cur = crumb.children;
        continue;
      }
      final refreshed = cur.where((n) => n.id == crumb.id).firstOrNull;
      if (refreshed == null) return const [];
      cur = refreshed.children;
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      return cur.where((t) => t.label.toLowerCase().contains(q)).toList();
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
    final isPresentation = topic.id.startsWith(_presentationTopicPrefix);
    try {
      final res = await _service.switchTopic(
        conversationId,
        topicId: isPresentation ? null : topic.id,
        label: isPresentation ? topic.label : null,
      );
      if (res.topic != null) {
        _selectedTopic = _selectedTopic?.copyWith(
          id: res.topic!.id,
          parentId: res.topic!.parentId,
          parentLabel: res.topic!.parentLabel,
          description: res.topic!.description ?? _selectedTopic?.description,
        );
      }
      onTopicSwitched?.call();
      if (topic.origin != TopicOrigin.suggested) {
        unawaited(_service.prepare(topic.id));
      }
    } catch (_) {
      try {
        await _service.activateTopic(
          conversationId,
          topicId: isPresentation ? null : topic.id,
          label: isPresentation ? topic.label : null,
        );
        onTopicSwitched?.call();
        if (topic.origin != TopicOrigin.suggested) {
          unawaited(_service.prepare(topic.id));
        }
      } catch (e) {
        _selectedTopic = topic.copyWith(
          contextStatus: TopicContextStatus.limited,
        );
        _error = _kLimited;
        logDebug('Failed to activate topic: $e');
        notifyListeners();
      }
    }
  }

  Future<void> activateFreeText(String conversationId, String label) async {
    final topic = TopicNode(
      id: 'provisional-${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      origin: _mode,
      contextStatus: TopicContextStatus.ready,
    );
    _selectedTopic = topic;
    _showLanding = false;
    notifyListeners();
    try {
      await _service.switchTopic(conversationId, label: label);
      onTopicSwitched?.call();
    } catch (_) {
      try {
        await _service.activateTopic(conversationId, label: label);
        onTopicSwitched?.call();
      } catch (_) {
        _selectedTopic = topic.copyWith(
          contextStatus: TopicContextStatus.limited,
        );
        _error = _kLimited;
        notifyListeners();
      }
    }
  }

  void startNewTopic() {
    _selectedTopic = null;
    _path = const [];
    _showLanding = true;
    _error = null;
    notifyListeners();
    unawaited(load());
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

  List<TopicNode> _presentationHierarchy(List<TopicNode> roots) {
    if (_mode != TopicOrigin.personal ||
        roots.any((t) => t.children.isNotEmpty)) {
      return roots;
    }
    final byLead = <String, List<TopicNode>>{};
    for (final t in roots) {
      final lead = t.label
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .firstWhere((w) => w.isNotEmpty, orElse: () => '');
      if (lead.length >= 3 && lead != 'test' && lead != 'search') {
        byLead.putIfAbsent(lead, () => []).add(t);
      }
    }
    final groupedIds = <String>{};
    final replacements = <String, TopicNode>{};
    for (final e in byLead.entries) {
      if (e.value.length < 2) continue;
      final label = switch (e.key) {
        'time' => 'World time',
        'tax' || 'taxes' => 'Taxes',
        _ => e.key[0].toUpperCase() + e.key.substring(1),
      };
      final children = [...e.value]..sort((a, b) => b.score.compareTo(a.score));
      groupedIds.addAll(children.map((t) => t.id));
      replacements[children.first.id] = TopicNode(
        id: '$_presentationTopicPrefix${e.key}',
        label: label,
        origin: TopicOrigin.history,
        score: children.map((t) => t.score).reduce((a, b) => a > b ? a : b),
        signal: 'from your history',
        childCount: children.length,
        children: children,
      );
    }
    if (replacements.isEmpty) return roots;
    return [
      for (final r in roots)
        if (replacements.containsKey(r.id))
          replacements[r.id]!
        else if (!groupedIds.contains(r.id))
          r,
    ];
  }
}
