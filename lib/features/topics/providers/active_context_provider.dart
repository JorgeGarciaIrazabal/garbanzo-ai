import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/services/active_context_service.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';

class ActiveContextProvider extends ChangeNotifier {
  ActiveContextProvider({
    ActiveContextService? service,
    TopicService? topicService,
  }) : _service = service ?? ActiveContextService.instance,
       _topicService = topicService ?? TopicService.instance;

  final ActiveContextService _service;
  final TopicService _topicService;

  ActiveContext? _context;
  ActiveContext? get context => _context;

  List<ActiveContextItem> get carryoverItems =>
      _context?.items
          .where((item) => item.sourceType == 'carryover')
          .toList(growable: false) ??
      const [];

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> load(String conversationId, {bool quiet = false}) async {
    if (!quiet) {
      _loading = true;
      notifyListeners();
    }
    try {
      _context = await _service.getContext(conversationId);
      _error = null;
    } catch (error) {
      _error = 'Active context is temporarily unavailable';
      logDebug('Failed to load active context: $error');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void applyContextUpdate(Map<String, dynamic> payload) {
    final current = _context;
    final incomingVersion = (payload['context_version'] as num?)?.toInt();
    if (current != null &&
        incomingVersion != null &&
        incomingVersion < current.version) {
      return;
    }
    if (current != null && !payload.containsKey('pinned_items')) {
      final activeTopic = payload['active_topic'];
      _context = current.copyWith(
        version: incomingVersion ?? current.version,
        topic: activeTopic is Map<String, dynamic>
            ? TopicNode.fromJson({
                'origin': 'history',
                'score': 1,
                'child_count': 0,
                'children': const [],
                'starter_prompts': const [],
                'can_start': true,
                ...activeTopic,
              })
            : current.topic,
      );
      notifyListeners();
      return;
    }
    final incoming = ActiveContext.fromJson(payload);
    if (current == null || incoming.version >= current.version) {
      _context = incoming;
      notifyListeners();
    }
  }

  /// Resets the context to a fresh state after a topic switch.
  /// The new context comes from the server response and includes any carryover items.
  void resetFromServer(ActiveContext newContext) {
    _context = newContext;
    _error = null;
    notifyListeners();
  }

  Future<void> setItemState(String itemId, ActiveContextItemState state) async {
    final current = _context;
    if (current == null) return;
    final before = current;
    _context = current.copyWith(
      items: [
        for (final item in current.items)
          if (item.id == itemId) item.copyWith(state: state) else item,
      ],
    );
    notifyListeners();
    try {
      await _mutateWithOneConflictRetry(itemId, state, before);
      _context = await _service.getContext(before.conversationId);
      _error = null;
    } catch (error) {
      _context = before;
      _error = 'Could not update this context source';
      logDebug('Failed to update context item: $error');
    }
    notifyListeners();
  }

  Future<void> _mutateWithOneConflictRetry(
    String itemId,
    ActiveContextItemState state,
    ActiveContext base,
  ) async {
    try {
      await _service.mutateItem(
        base.conversationId,
        itemId,
        state: state,
        contextVersion: base.version,
      );
    } on ActiveContextServiceException catch (error) {
      if (error.statusCode != 409) rethrow;
      final latest = await _service.getContext(base.conversationId);
      await _service.mutateItem(
        base.conversationId,
        itemId,
        state: state,
        contextVersion: latest.version,
      );
    }
  }

  Future<void> addSource({
    required String sourceType,
    required String sourceId,
  }) async {
    final current = _context;
    if (current == null) return;
    try {
      await _service.addSource(
        current.conversationId,
        sourceType: sourceType,
        sourceId: sourceId,
        contextVersion: current.version,
      );
      _context = await _service.getContext(current.conversationId);
      _error = null;
    } catch (error) {
      _error = 'Could not add this context source';
      logDebug('Failed to add context source: $error');
    }
    notifyListeners();
  }

  Future<void> setTopicPinned(bool pinned) async {
    final current = _context;
    if (current == null) return;
    _context = current.copyWith(topicPinned: pinned);
    notifyListeners();
    try {
      await _topicService.setTopicPinned(
        current.conversationId,
        pinned: pinned,
        contextVersion: current.version,
      );
    } catch (error) {
      _context = current;
      _error = 'Could not update topic pin';
      notifyListeners();
    }
  }
}
