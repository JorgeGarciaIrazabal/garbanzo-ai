import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';

TopicSwitchResponse _response({
  required String conversationId,
  TopicSwitchTopic? topic,
  TopicContextStatus contextStatus = TopicContextStatus.preparing,
  List<ActiveContextItem> retainedItems = const [],
  String idempotencyKey = 'server-action-key',
  bool archived = true,
}) => TopicSwitchResponse(
  conversationId: conversationId,
  topic: topic,
  contextVersion: 1,
  sessionEpoch: 2,
  archived: archived,
  retainedItems: retainedItems,
  contextStatus: contextStatus,
  idempotencyKey: idempotencyKey,
);

class _FakeTopicService extends TopicService {
  _FakeTopicService({
    List<TopicNode> personalTopics = const [],
    List<TopicNode> exploreTopics = const [],
    this.switchResult,
    this.switchError,
    this.onListTopics,
  }) : _topics = {
         TopicOrigin.personal: personalTopics,
         TopicOrigin.explore: exploreTopics,
       },
       super.forTesting();

  final Map<TopicOrigin, List<TopicNode>> _topics;
  final TopicSwitchResponse? switchResult;
  final Object? switchError;
  final Future<List<TopicNode>> Function(TopicOrigin mode)? onListTopics;
  String? activatedTopicId;
  String? activatedLabel;
  String? lastMode;
  String? lastIdempotencyKey;
  bool? lastRetainPinned;

  @override
  Future<List<TopicNode>> listTopics(TopicOrigin mode) =>
      onListTopics?.call(mode) ?? Future.value(_topics[mode] ?? const []);

  @override
  Future<TopicSwitchResponse> switchTopic(
    String conversationId, {
    String? topicId,
    String? label,
    bool archive = true,
    bool retainPinned = true,
    required String idempotencyKey,
    String mode = 'switch',
  }) async {
    activatedTopicId = topicId;
    activatedLabel = label;
    lastMode = mode;
    lastIdempotencyKey = idempotencyKey;
    lastRetainPinned = retainPinned;
    if (switchError != null) throw switchError!;
    return switchResult ??
        _response(
          conversationId: conversationId,
          archived: archive,
          topic: TopicSwitchTopic(
            id: topicId ?? 'created-topic',
            label: label ?? topicId ?? 'Created topic',
            pinned: true,
          ),
        );
  }
}

class _ContractTopicService extends TopicService {
  _ContractTopicService({required this.response}) : super.forTesting();

  Response<dynamic> response;
  Map<String, dynamic>? switchPayload;

  @override
  Future<Response<dynamic>> getTopicListResponse(TopicOrigin mode) async =>
      response;

  @override
  Future<Response<dynamic>> postTopicSwitch(
    String conversationId,
    Map<String, dynamic> data,
  ) async {
    switchPayload = data;
    return response;
  }
}

Response<dynamic> _httpResponse(Object? data, {int statusCode = 200}) =>
    Response<dynamic>(
      data: data,
      statusCode: statusCode,
      requestOptions: RequestOptions(path: '/api/v1/chat/topics'),
    );

void main() {
  final child = TopicNode(
    id: '401k',
    parentId: 'retirement',
    label: '401(k) contributions',
    origin: TopicOrigin.personal,
  );
  final parent = TopicNode(
    id: 'retirement',
    label: 'Retirement planning',
    origin: TopicOrigin.personal,
    children: [child],
  );

  test('keeps navigation path while applying a nested live topic update', () async {
    final service = _FakeTopicService(personalTopics: [parent]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.load();
    provider.openChildren(parent);

    provider.applyTopicUpdate({
      'id': '401k',
      'parent_id': 'retirement',
      'label': 'Updated contribution plan',
      'origin': 'personal',
      'context_status': 'ready',
    });

    expect(provider.path.single.id, 'retirement');
    expect(provider.visibleTopics.single.label, 'Updated contribution plan');
    expect(provider.visibleTopics.single.contextStatus, TopicContextStatus.ready);
  });

  test('stores a load response in its requested mode after mode changes', () async {
    final personalLoad = Completer<List<TopicNode>>();
    const personal = TopicNode(
      id: 'personal-topic',
      label: 'Personal topic',
      origin: TopicOrigin.personal,
    );
    const explore = TopicNode(
      id: 'explore-topic',
      label: 'Explore topic',
      origin: TopicOrigin.explore,
    );
    final service = _FakeTopicService(
      exploreTopics: [explore],
      onListTopics: (mode) => mode == TopicOrigin.personal
          ? personalLoad.future
          : Future.value([explore]),
    );
    final provider = TopicDiscoveryProvider(service: service);

    final loadingPersonal = provider.load();
    final switchingMode = provider.setMode(TopicOrigin.explore);
    personalLoad.complete([personal]);
    await loadingPersonal;
    await switchingMode;

    expect(provider.mode, TopicOrigin.explore);
    expect(provider.topics.single.id, explore.id);
    await provider.setMode(TopicOrigin.personal);
    expect(provider.topics.single.id, personal.id);
  });

  test('uses the server-owned tree without synthetic presentation topics', () async {
    const tokyo = TopicNode(
      id: 'tokyo',
      label: 'Time Tokyo',
      origin: TopicOrigin.history,
    );
    const madrid = TopicNode(
      id: 'madrid',
      label: 'Time Madrid',
      origin: TopicOrigin.history,
    );
    final provider = TopicDiscoveryProvider(
      service: _FakeTopicService(personalTopics: [tokyo, madrid]),
    );

    await provider.load();

    expect(provider.topics.map((topic) => topic.id), ['tokyo', 'madrid']);
    expect(provider.topics.map((topic) => topic.label), ['Time Tokyo', 'Time Madrid']);
  });

  test('searches the full tree and retains each matching descendant path', () async {
    const matchingLeaf = TopicNode(
      id: 'contributions',
      parentId: 'retirement',
      label: 'Contribution limits',
      origin: TopicOrigin.personal,
    );
    const nestedParent = TopicNode(
      id: 'retirement',
      parentId: 'finance',
      label: 'Retirement',
      origin: TopicOrigin.personal,
      children: [matchingLeaf],
    );
    const root = TopicNode(
      id: 'finance',
      label: 'Finance',
      origin: TopicOrigin.personal,
      children: [nestedParent],
    );
    final provider = TopicDiscoveryProvider(
      service: _FakeTopicService(personalTopics: [root]),
    );
    await provider.load();

    provider.setSearchQuery('contribution');

    final result = provider.visibleTopics.single;
    expect(result.id, matchingLeaf.id);
    expect(result.parentLabel, 'Finance › Retirement');
  });

  test('activating applies the authoritative response and does not prepare again',
      () async {
    final serverTopic = TopicSwitchTopic(
      id: 'canonical-id',
      label: 'Canonical topic',
      parentId: 'parent-id',
      parentLabel: 'Canonical parent',
      description: 'Server description',
      pinned: true,
    );
    final retained = ActiveContextItem(
      id: 'pinned-item',
      sourceType: 'message',
      sourceId: 'message-1',
      state: ActiveContextItemState.pinned,
      reason: 'User retained this source',
    );
    final service = _FakeTopicService(
      switchResult: _response(
        conversationId: 'primary-conversation',
        topic: serverTopic,
        contextStatus: TopicContextStatus.preparing,
        retainedItems: [retained],
        idempotencyKey: 'server-key',
      ),
    );
    final provider = TopicDiscoveryProvider(service: service);

    await provider.activate('primary-conversation', child);

    expect(provider.showLanding, isFalse);
    expect(provider.selectedTopic?.id, 'canonical-id');
    expect(provider.selectedTopic?.label, 'Canonical topic');
    expect(provider.selectedTopic?.parentLabel, 'Canonical parent');
    expect(provider.contextStatus, TopicContextStatus.preparing);
    expect(provider.retainedItems, [retained]);
    expect(provider.lastSwitchIdempotencyKey, 'server-key');
  });

  test('server selection sync does not close the explicitly opened landing', () {
    final provider = TopicDiscoveryProvider(
      service: _FakeTopicService(personalTopics: [child]),
    );

    provider.setSelectedTopic(child);
    expect(provider.showLanding, isFalse);

    provider.startNewTopic();
    provider.synchronizeSelectedTopic(
      child.copyWith(contextStatus: TopicContextStatus.ready),
    );

    expect(provider.showLanding, isTrue);
    expect(provider.selectedTopic?.id, child.id);
    expect(provider.contextStatus, TopicContextStatus.ready);
  });

  test('free-text activation replaces its provisional selection with the server topic',
      () async {
    final service = _FakeTopicService(
      switchResult: _response(
        conversationId: 'primary-conversation',
        topic: TopicSwitchTopic(
          id: 'server-created-topic',
          label: 'Server-normalized label',
          pinned: true,
        ),
        contextStatus: TopicContextStatus.ready,
      ),
    );
    final provider = TopicDiscoveryProvider(service: service);

    await provider.activateFreeText('primary-conversation', 'New subject');

    expect(provider.selectedTopic?.id, 'server-created-topic');
    expect(provider.selectedTopic?.label, 'Server-normalized label');
    expect(provider.selectedTopic?.id, isNot(startsWith('provisional-')));
  });

  test('failed switching does not fall back to the legacy activate endpoint', () async {
    final service = _FakeTopicService(switchError: StateError('switch failed'));
    final provider = TopicDiscoveryProvider(service: service);

    await provider.activate('primary-conversation', child);

    expect(provider.contextStatus, TopicContextStatus.limited);
    expect(provider.error, isNotNull);
  });

  test('combine keeps combine behavior and sends a distinct action key', () async {
    final service = _FakeTopicService();
    final provider = TopicDiscoveryProvider(service: service);
    var combinedCount = 0;
    provider.onTopicCombined = (_) async => combinedCount++;

    await provider.combineTopics(
      'primary-conversation',
      topicId: 'topic-combine',
      idempotencyKey: 'combine-key',
    );

    expect(combinedCount, 1);
    expect(service.lastMode, 'combine');
    expect(service.lastIdempotencyKey, 'combine-key');
  });

  test('TopicService accepts only the current topic-list response shape', () async {
    final service = _ContractTopicService(
      response: _httpResponse({
        'mode': 'personal',
        'topics': [
          {
            'id': 'topic-1',
            'label': 'One',
            'origin': 'history',
          },
        ],
      }),
    );

    expect((await service.listTopics(TopicOrigin.personal)).single.id, 'topic-1');

    service.response = _httpResponse({'items': const []});
    await expectLater(
      service.listTopics(TopicOrigin.personal),
      throwsA(isA<FormatException>()),
    );
  });

  test('TopicService sends retention and idempotency fields without carryover',
      () async {
    final service = _ContractTopicService(
      response: _httpResponse({
        'conversation_id': 'primary-conversation',
        'topic': {
          'id': 'topic-1',
          'label': 'One',
          'pinned': true,
        },
        'context_version': 4,
        'session_epoch': 3,
        'archived': true,
        'retained_items': const [],
        'context_status': {'readiness': 'preparing'},
        'idempotency_key': 'switch-key',
      }),
    );

    final response = await service.switchTopic(
      'primary-conversation',
      topicId: 'topic-1',
      retainPinned: false,
      idempotencyKey: 'switch-key',
    );

    expect(service.switchPayload?['retain_pinned'], isFalse);
    expect(service.switchPayload?['idempotency_key'], 'switch-key');
    expect(service.switchPayload, isNot(contains('carryover')));
    expect(response.contextStatus, TopicContextStatus.preparing);
    expect(response.idempotencyKey, 'switch-key');

    await expectLater(
      service.switchTopic(
        'primary-conversation',
        topicId: 'topic-1',
        label: 'One',
        idempotencyKey: 'invalid-targets',
      ),
      throwsArgumentError,
    );
  });
}
