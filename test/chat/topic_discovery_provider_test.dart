import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';

class _FakeTopicService extends TopicService {
  _FakeTopicService(this.personalTopics) : super.forTesting();

  final List<TopicNode> personalTopics;
  final List<String> preparedTopicIds = [];
  String? activatedTopicId;
  String? activatedLabel;
  String? lastMode;

  @override
  Future<List<TopicNode>> listTopics(TopicOrigin mode) async =>
      mode == TopicOrigin.personal ? personalTopics : const [];

  @override
  Future<void> activateTopic(
    String conversationId, {
    String? topicId,
    String? label,
  }) async {
    activatedTopicId = topicId;
    activatedLabel = label;
  }

  @override
  Future<TopicSwitchResponse> switchTopic(
    String conversationId, {
    String? topicId,
    String? label,
    bool archive = true,
    int carryoverMaxItems = 5,
    int carryoverMaxTokens = 400,
    String mode = 'switch',
  }) async {
    activatedTopicId = topicId;
    activatedLabel = label;
    lastMode = mode;
    return TopicSwitchResponse(
      conversationId: conversationId,
      contextVersion: 1,
      archived: archive,
      carryover: const [],
      topic: topicId != null
          ? TopicSwitchTopic(
              id: topicId,
              label: label ?? topicId,
              pinned: true,
            )
          : null,
    );
  }

  @override
  Future<void> prepare(String topicId) async {
    preparedTopicIds.add(topicId);
  }
}

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
    final service = _FakeTopicService([parent]);
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

  test('activating a learned topic hides discovery and prewarms context', () async {
    final service = _FakeTopicService([parent]);
    final provider = TopicDiscoveryProvider(service: service);

    await provider.activate('primary-conversation', child);
    await Future<void>.delayed(Duration.zero);

    expect(provider.showLanding, isFalse);
    expect(provider.selectedTopic?.id, child.id);
    expect(provider.contextStatus, TopicContextStatus.preparing);
    expect(service.activatedTopicId, child.id);
    expect(service.preparedTopicIds, [child.id]);
  });

  test('new topic restores discovery without discarding the cached topic tree', () async {
    final service = _FakeTopicService([parent]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.load();
    await provider.activate('primary-conversation', child);

    provider.startNewTopic();

    expect(provider.showLanding, isTrue);
    expect(provider.selectedTopic, isNull);
    expect(provider.topics.single.id, parent.id);
  });

  test('renders an obvious flat time pair as a selectable presentation branch', () async {
    final tokyo = TopicNode(
      id: 'tokyo',
      label: 'Time Tokyo',
      origin: TopicOrigin.history,
      score: 0.9,
    );
    final madrid = TopicNode(
      id: 'madrid',
      label: 'Time Madrid',
      origin: TopicOrigin.history,
      score: 0.8,
    );
    final service = _FakeTopicService([tokyo, madrid]);
    final provider = TopicDiscoveryProvider(service: service);

    await provider.load();

    final worldTime = provider.topics.single;
    expect(worldTime.id, 'presentation:time');
    expect(worldTime.label, 'World time');
    expect(worldTime.children.map((topic) => topic.id), ['tokyo', 'madrid']);

    provider.openChildren(worldTime);
    expect(provider.visibleTopics.map((topic) => topic.id), ['tokyo', 'madrid']);
    await provider.activate('primary-conversation', worldTime);
    expect(service.activatedTopicId, isNull);
    expect(service.activatedLabel, 'World time');
  });

  test('filters visible topics by search query', () async {
    final t1 = TopicNode(id: '1', label: 'Flutter App', origin: TopicOrigin.personal);
    final t2 = TopicNode(id: '2', label: 'Backend Database', origin: TopicOrigin.personal);
    final service = _FakeTopicService([t1, t2]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.load();

    expect(provider.visibleTopics.length, 2);

    provider.setSearchQuery('flutter');
    expect(provider.visibleTopics.single.id, '1');

    provider.setSearchQuery('data');
    expect(provider.visibleTopics.single.id, '2');

    provider.setSearchQuery('');
    expect(provider.visibleTopics.length, 2);
  });

  test('handles topic drift proposals, dismissal, and acceptance', () async {
    final service = _FakeTopicService([]);
    final provider = TopicDiscoveryProvider(service: service);

    expect(provider.pendingDrift, isNull);

    provider.applyTopicDrift({
      'topic_drift': {
        'detected_topic_id': 'topic-fitness',
        'label': 'Fitness Routine',
        'confidence': 0.85,
      },
    });

    expect(provider.pendingDrift?.detectedTopicId, 'topic-fitness');
    expect(provider.pendingDrift?.label, 'Fitness Routine');
    expect(provider.pendingDrift?.confidence, 0.85);

    provider.dismissDrift();
    expect(provider.pendingDrift, isNull);
  });

  test('invokes onTopicSwitched callback on activate and switchTopic', () async {
    final service = _FakeTopicService([parent]);
    final provider = TopicDiscoveryProvider(service: service);
    var switchCount = 0;
    provider.onTopicSwitched = () => switchCount++;

    await provider.activate('primary-conversation', child);
    expect(switchCount, 1);

    await provider.switchTopic('primary-conversation', topicId: 'new-id');
    expect(switchCount, 2);
  });

  test('invokes onTopicCombined callback and passes mode combine on combineTopics', () async {
    final service = _FakeTopicService([parent]);
    final provider = TopicDiscoveryProvider(service: service);
    var combinedCount = 0;
    var switchCount = 0;
    provider.onTopicCombined = () => combinedCount++;
    provider.onTopicSwitched = () => switchCount++;

    await provider.combineTopics('primary-conversation', topicId: 'topic-combine');
    expect(combinedCount, 1);
    expect(switchCount, 0);
    expect(service.lastMode, 'combine');
    expect(service.activatedTopicId, 'topic-combine');
  });
}
