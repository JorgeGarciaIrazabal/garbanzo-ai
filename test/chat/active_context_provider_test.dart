import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/features/topics/services/active_context_service.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';

class _FakeActiveContextService extends ActiveContextService {
  _FakeActiveContextService(this.latest) : super.forTesting();

  ActiveContext latest;
  bool conflictOnce = false;
  final List<int> mutationVersions = [];

  @override
  Future<ActiveContext> getContext(String conversationId) async => latest;

  @override
  Future<ActiveContext> mutateItem(
    String conversationId,
    String itemId, {
    required ActiveContextItemState state,
    required int contextVersion,
  }) async {
    mutationVersions.add(contextVersion);
    if (conflictOnce) {
      conflictOnce = false;
      throw const ActiveContextServiceException(409);
    }
    latest = latest.copyWith(
      version: contextVersion + 1,
      items: [
        for (final item in latest.items)
          if (item.id == itemId) item.copyWith(state: state) else item,
      ],
    );
    return latest;
  }
}

class _FakeTopicService extends TopicService {
  _FakeTopicService() : super.forTesting();

  bool? lastPinned;
  int? lastVersion;

  @override
  Future<void> setTopicPinned(
    String conversationId, {
    required bool pinned,
    required int contextVersion,
  }) async {
    lastPinned = pinned;
    lastVersion = contextVersion;
  }
}

ActiveContext _context({int version = 1}) => ActiveContext(
  conversationId: 'primary',
  version: version,
  readiness: ActiveContextReadiness.ready,
  items: const [
    ActiveContextItem(
      id: 'source-1',
      sourceType: 'message',
      sourceId: 'message-1',
      state: ActiveContextItemState.dynamic,
      reason: 'Relevant evidence',
    ),
  ],
);

void main() {
  test('ignores a stale SSE context update', () async {
    final service = _FakeActiveContextService(_context(version: 3));
    final provider = ActiveContextProvider(service: service);
    await provider.load('primary');

    provider.applyContextUpdate({
      'conversation_id': 'primary',
      'context_version': 2,
      'readiness': 'limited',
    });

    expect(provider.context?.version, 3);
    expect(provider.context?.readiness, ActiveContextReadiness.ready);
  });

  test('retries one optimistic item update after a version conflict', () async {
    final service = _FakeActiveContextService(_context(version: 1));
    service.conflictOnce = true;
    final provider = ActiveContextProvider(service: service);
    await provider.load('primary');
    service.latest = _context(version: 4);

    await provider.setItemState('source-1', ActiveContextItemState.pinned);

    expect(service.mutationVersions, [1, 4]);
    expect(provider.context?.version, 5);
    expect(provider.context?.pinnedItems.single.id, 'source-1');
    expect(provider.error, isNull);
  });

  test('pinning a topic uses the current optimistic context version', () async {
    final contextService = _FakeActiveContextService(_context(version: 6));
    final topicService = _FakeTopicService();
    final provider = ActiveContextProvider(
      service: contextService,
      topicService: topicService,
    );
    await provider.load('primary');

    await provider.setTopicPinned(true);

    expect(provider.context?.topicPinned, isTrue);
    expect(topicService.lastPinned, isTrue);
    expect(topicService.lastVersion, 6);
  });
}
