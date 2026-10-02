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

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;
  String? _conversationId;
  int _requestEpoch = 0;

  void bindConversation(String? conversationId) {
    if (_conversationId == conversationId) return;
    _conversationId = conversationId;
    _requestEpoch++;
    _context = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  bool _ownsRequest(String conversationId, int epoch) =>
      _conversationId == conversationId && _requestEpoch == epoch;

  Future<void> load(String conversationId, {bool quiet = false}) async {
    bindConversation(conversationId);
    final epoch = ++_requestEpoch;
    if (!quiet) {
      _loading = true;
      notifyListeners();
    }
    try {
      final loaded = await _service.getContext(conversationId);
      if (!_ownsRequest(conversationId, epoch)) return;
      _context = loaded;
      _error = null;
    } catch (error) {
      if (!_ownsRequest(conversationId, epoch)) return;
      _error = 'Active context is temporarily unavailable';
      logDebug('Failed to load active context: $error');
    } finally {
      if (_ownsRequest(conversationId, epoch)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void applyContextUpdate(Map<String, dynamic> payload) {
    final conversationId = payload['conversation_id'] as String?;
    if (conversationId != null && conversationId != _conversationId) return;
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
  /// Replace local state with the server's authoritative context snapshot.
  void resetFromServer(ActiveContext newContext) {
    _conversationId = newContext.conversationId;
    _requestEpoch++;
    _context = newContext;
    _error = null;
    notifyListeners();
  }

  Future<void> setItemState(String itemId, ActiveContextItemState state) async {
    final current = _context;
    if (current == null) return;
    final before = current;
    final epoch = _requestEpoch;
    _context = current.copyWith(
      items: [
        for (final item in current.items)
          if (item.id == itemId) item.copyWith(state: state) else item,
      ],
    );
    notifyListeners();
    try {
      await _mutateWithOneConflictRetry(itemId, state, before);
      final loaded = await _service.getContext(before.conversationId);
      if (!_ownsRequest(before.conversationId, epoch)) return;
      _context = loaded;
      _error = null;
    } catch (error) {
      if (!_ownsRequest(before.conversationId, epoch)) return;
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
    final epoch = _requestEpoch;
    try {
      await _service.addSource(
        current.conversationId,
        sourceType: sourceType,
        sourceId: sourceId,
        contextVersion: current.version,
      );
      final loaded = await _service.getContext(current.conversationId);
      if (!_ownsRequest(current.conversationId, epoch)) return;
      _context = loaded;
      _error = null;
    } catch (error) {
      if (!_ownsRequest(current.conversationId, epoch)) return;
      _error = 'Could not add this context source';
      logDebug('Failed to add context source: $error');
    }
    notifyListeners();
  }

  Future<void> setTopicPinned(bool pinned) async {
    final current = _context;
    if (current == null) return;
    final epoch = _requestEpoch;
    _context = current.copyWith(topicPinned: pinned);
    notifyListeners();
    try {
      await _topicService.setTopicPinned(
        current.conversationId,
        pinned: pinned,
        contextVersion: current.version,
      );
      final loaded = await _service.getContext(current.conversationId);
      if (!_ownsRequest(current.conversationId, epoch)) return;
      _context = loaded;
      _error = null;
      notifyListeners();
    } catch (error) {
      if (!_ownsRequest(current.conversationId, epoch)) return;
      _context = current;
      _error = 'Could not update topic pin';
      notifyListeners();
    }
  }
}
