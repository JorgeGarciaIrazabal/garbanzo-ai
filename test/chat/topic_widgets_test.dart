import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_page.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_message_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/topic_banner.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/services/active_context_service.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';
import 'package:garbanzo_ai/features/topics/widgets/active_context_panel.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_context_empty_state.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_greeting_card.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_landing.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_switch_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChatProvider extends ChatProvider {
  _FakeChatProvider({
    List<ChatMessage> messages = const [],
    Conversation? conversation,
  }) : _initialMessages = messages,
       _conversation = conversation;

  final List<ChatMessage> _initialMessages;
  final Conversation? _conversation;
  final List<Map<String, dynamic>> createdConversations = [];
  final List<Map<String, dynamic>> sentMessages = [];
  String? loadedConversationId;

  @override
  List<ChatMessage> get messages => _initialMessages;

  @override
  Conversation? get currentConversation => _conversation;

  @override
  Future<void> loadConversation(String conversationId) async {
    loadedConversationId = conversationId;
  }

  @override
  Future<Conversation?> createConversation({
    String? title,
    String? model,
    String? initialMessage,
    String? systemPrompt,
    ThinkingLevel? thinkingLevel,
    String? activeTopicId,
    List<ChatAttachment> initialAttachments = const [],
  }) async {
    createdConversations.add({
      'title': title,
      'model': model,
      'initialMessage': initialMessage,
      'initialAttachments': initialAttachments,
      'activeTopicId': activeTopicId,
    });
    return Conversation(
      id: 'thread-1',
      title: title,
      model: model ?? 'llama3.2',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      activeTopicId: activeTopicId,
    );
  }

  @override
  Future<void> sendMessage(
    String content, {
    List<ChatAttachment> attachments = const [],
    String? talkModeInstruction,
  }) async {
    sentMessages.add({'message': content, 'attachments': attachments});
  }
}

class _FakeTopicService extends TopicService {
  _FakeTopicService(
    this.topics, {
    this.archives = const [],
    this.archivePage,
  }) : super.forTesting();
  final List<TopicNode> topics;
  final List<TopicArchive> archives;
  final TopicArchivePage? archivePage;

  @override
  Future<List<TopicNode>> listTopics(TopicOrigin mode) async => topics;

  @override
  Future<List<TopicArchive>> listArchives(String topicId) async => archives;

  @override
  Future<TopicArchivePage> getArchivePage(
    String topicId,
    String archiveId, {
    String? before,
    int limit = 100,
  }) async => archivePage!;

  TopicNode? _topicById(String? id) {
    for (final topic in topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

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
    if ((topicId == null) == (label == null)) {
      throw StateError('exactly one topic target is required');
    }
    final selected = _topicById(topicId);
    return TopicSwitchResponse(
        conversationId: conversationId,
        contextVersion: 2,
        sessionEpoch: 1,
        archived: archive,
        retainedItems: const [],
        contextStatus: TopicContextStatus.preparing,
        idempotencyKey: idempotencyKey,
        topic: TopicSwitchTopic(
          id: topicId ?? 'created-topic',
          label: label ?? selected?.label ?? topicId ?? 'Created topic',
          parentId: selected?.parentId,
          parentLabel: selected?.parentLabel,
          description: selected?.description,
          pinned: true,
        ),
      );
  }
}

class _FakeActiveContextService extends ActiveContextService {
  _FakeActiveContextService(this.activeContext) : super.forTesting();
  final ActiveContext activeContext;
  String? addedSourceId;

  @override
  Future<ActiveContext> getContext(String conversationId) async => activeContext;

  @override
  Future<int> addSource(
    String conversationId, {
    required String sourceType,
    required String sourceId,
    required int contextVersion,
  }) async {
    addedSourceId = sourceId;
    return contextVersion + 1;
  }
}

Widget _wrapWithApp(
  Widget child, {
  TopicDiscoveryProvider? topicProvider,
  ActiveContextProvider? contextProvider,
  ChatProvider? chatProvider,
  SettingsProvider? settingsProvider,
}) =>
    MultiProvider(
      providers: [
        if (topicProvider != null) ChangeNotifierProvider.value(value: topicProvider),
        if (contextProvider != null) ChangeNotifierProvider.value(value: contextProvider),
        if (chatProvider != null) ChangeNotifierProvider.value(value: chatProvider),
        if (settingsProvider != null) ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unselected Topics landing composer starts a regular thread', () async {
    final topics = TopicDiscoveryProvider(service: _FakeTopicService(const []));
    final chat = _FakeChatProvider(
      conversation: Conversation(
        id: 'primary',
        model: 'kimi-k3',
        isPrimary: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    final attachment = ChatAttachment(
      name: 'photo.png',
      mimeType: 'image/png',
      type: AttachmentType.image,
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    await submitChatComposerMessage(
      chatProvider: chat,
      topicDiscovery: topics,
      message: '',
      attachments: [attachment],
    );

    expect(chat.createdConversations, hasLength(1));
    expect(chat.createdConversations.single['activeTopicId'], isNull);
    expect(chat.createdConversations.single['initialAttachments'], [attachment]);
    expect(chat.sentMessages, isEmpty);
  });

  test('selected topic composer stays in the primary conversation', () async {
    const selected = TopicNode(
      id: 'topic-1',
      label: 'Selected topic',
      origin: TopicOrigin.personal,
    );
    final topics = TopicDiscoveryProvider(service: _FakeTopicService(const []))
      ..setSelectedTopic(selected);
    final chat = _FakeChatProvider(
      conversation: Conversation(
        id: 'primary',
        model: 'kimi-k3',
        isPrimary: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

    await submitChatComposerMessage(
      chatProvider: chat,
      topicDiscovery: topics,
      message: 'Evaluate this',
      attachments: const [],
    );

    expect(chat.createdConversations, isEmpty);
    expect(chat.sentMessages.single['message'], 'Evaluate this');
  });

  test(
    'landing send starts a clean thread even when the server has synced a selection',
    () async {
      // Regression for user report 41c79409: the primary's persisted active
      // topic is pushed back into selectedTopic a frame after the landing
      // opens (synchronizeSelectedTopic), without closing the landing. A send
      // from the map must still open an empty regular thread — not append to
      // the primary's already-loaded history.
      const synced = TopicNode(
        id: 'topic-1',
        label: 'Previously active topic',
        origin: TopicOrigin.history,
      );
      final topics = TopicDiscoveryProvider(service: _FakeTopicService(const []))
        ..startNewTopic()
        ..synchronizeSelectedTopic(synced);
      final chat = _FakeChatProvider(
        messages: [
          ChatMessage(
            id: 'm1',
            role: 'user',
            content: 'old message from the primary',
            createdAt: DateTime(2026),
          ),
        ],
        conversation: Conversation(
          id: 'primary',
          model: 'kimi-k3',
          isPrimary: true,
          activeTopicId: 'topic-1',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      await submitChatComposerMessage(
        chatProvider: chat,
        topicDiscovery: topics,
        message: 'fresh question',
        attachments: const [],
      );

      expect(topics.showLanding, isTrue);
      expect(chat.createdConversations, hasLength(1));
      expect(chat.createdConversations.single['activeTopicId'], isNull);
      expect(chat.sentMessages, isEmpty);
    },
  );

  testWidgets('TopicBanner renders active topic and topic drift chip with dismiss action', (tester) async {
    final t1 = TopicNode(
      id: 'topic-1',
      label: 'Cooking Pasta',
      origin: TopicOrigin.personal,
      contextStatus: TopicContextStatus.ready,
    );
    final service = _FakeTopicService([t1]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.activate('c1', t1);

    await tester.pumpWidget(_wrapWithApp(const TopicBanner(), topicProvider: provider));
    await tester.pumpAndSettle();
    expect(find.text('Cooking Pasta'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_drift_banner')), findsNothing);

    // Apply drift
    provider.applyTopicDrift({
      'topic_drift': {
        'detected_topic_id': 'topic-2',
        'label': 'Gym Workout',
        'confidence': 0.88,
      },
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_drift_banner')), findsOneWidget);
    expect(find.text('Shift detected: switch to Gym Workout?'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_drift_switch_button')), findsOneWidget);

    // Tap dismiss
    await tester.tap(find.byKey(const ValueKey('topic_drift_dismiss_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_drift_banner')), findsNothing);
    expect(provider.pendingDrift, isNull);
  });

  testWidgets('TopicLanding search bar filters visible topics and clear button resets query', (tester) async {
    final t1 = TopicNode(id: '1', label: 'Machine Learning', origin: TopicOrigin.personal);
    final t2 = TopicNode(id: '2', label: 'Web Development', origin: TopicOrigin.personal);
    final service = _FakeTopicService([t1, t2]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.load();

    await tester.pumpWidget(
      _wrapWithApp(
        TopicLanding(
          conversationId: 'c1',
          onStarterSelected: (_) {},
        ),
        topicProvider: provider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Machine Learning'), findsOneWidget);
    expect(find.text('Web Development'), findsOneWidget);

    // Enter search text
    await tester.enterText(find.byKey(const ValueKey('topic_search_input')), 'web');
    await tester.pumpAndSettle();

    expect(find.text('Web Development'), findsOneWidget);
    expect(find.text('Machine Learning'), findsNothing);

    // Clear search
    await tester.tap(find.byKey(const ValueKey('topic_search_clear')));
    await tester.pumpAndSettle();

    expect(find.text('Machine Learning'), findsOneWidget);
    expect(find.text('Web Development'), findsOneWidget);
  });

  testWidgets('TopicLanding search shows a matching descendant parent path', (tester) async {
    const matchingLeaf = TopicNode(
      id: 'contributions',
      parentId: 'retirement',
      label: 'Contribution limits',
      origin: TopicOrigin.personal,
    );
    const parent = TopicNode(
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
      children: [parent],
    );
    final provider = TopicDiscoveryProvider(
      service: _FakeTopicService([root]),
    );
    await provider.load();

    await tester.pumpWidget(
      _wrapWithApp(
        TopicLanding(conversationId: 'c1', onStarterSelected: (_) {}),
        topicProvider: provider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('topic_search_input')),
      'contribution',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subtopic_marker_contributions')),
      findsOneWidget,
    );
    expect(find.text('Subtopic in Finance › Retirement'), findsOneWidget);
  });

  testWidgets('TopicLanding directly activates topic without switch dialog when no topic was selected', (tester) async {
    final t1 = const TopicNode(id: '1', label: 'Machine Learning', origin: TopicOrigin.personal);
    final service = _FakeTopicService([t1]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.load();

    await tester.pumpWidget(
      _wrapWithApp(
        TopicLanding(
          conversationId: 'c1',
          onStarterSelected: (_) {},
        ),
        topicProvider: provider,
      ),
    );
    await tester.pumpAndSettle();

    expect(provider.selectedTopic, isNull);
    await tester.tap(find.text('Machine Learning'));
    await tester.pumpAndSettle();

    // Dialog should NOT be shown
    expect(find.byKey(const ValueKey('topic_switch_dialog')), findsNothing);
    // Topic is directly activated
    expect(provider.selectedTopic?.label, 'Machine Learning');
  });

  testWidgets('parent topic can start directly and exposes a separate subtopic browser', (
    tester,
  ) async {
    const children = [
      TopicNode(
        id: 'stories',
        parentId: 'family',
        label: 'Fun Stories for Clara',
        origin: TopicOrigin.personal,
      ),
      TopicNode(
        id: 'school',
        parentId: 'family',
        label: 'Clara School',
        origin: TopicOrigin.personal,
      ),
    ];
    const family = TopicNode(
      id: 'family',
      label: 'Family & Clara',
      origin: TopicOrigin.personal,
      children: children,
    );
    final provider = TopicDiscoveryProvider(
      service: _FakeTopicService([family]),
    );
    await provider.load();

    await tester.pumpWidget(
      _wrapWithApp(
        TopicLanding(conversationId: 'primary', onStarterSelected: (_) {}),
        topicProvider: provider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Family & Clara'));
    await tester.pumpAndSettle();
    expect(provider.selectedTopic?.id, family.id);

    provider.startNewTopic();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('browse_subtopics_family')));
    await tester.pumpAndSettle();
    expect(provider.selectedTopic, isNull);
    expect(provider.path.map((topic) => topic.id), [family.id]);
    expect(find.text('Fun Stories for Clara'), findsOneWidget);
    expect(find.text('Clara School'), findsOneWidget);
  });

  testWidgets('ActiveContextPanel displays evidence provenance chip', (tester) async {
    final item = ActiveContextItem(
      id: 'item-1',
      sourceType: 'message',
      sourceId: 'msg-123456789',
      state: ActiveContextItemState.dynamic,
      reason: 'Explicit user statement in turn',
      title: 'Database selection',
      preview: 'PostgreSQL database',
      sourceExcerpt: 'We selected PostgreSQL for the application database.',
      sourceLabel: 'Architecture chat',
      sourceCreatedAt: DateTime(2026, 9, 5),
      sourceConversationId: 'source-chat',
    );
    final activeContext = ActiveContext(
      conversationId: 'c1',
      topic: null,
      version: 1,
      readiness: ActiveContextReadiness.ready,
      items: [item],
      tokenCount: 150,
      tokenBudget: 4000,
    );
    final service = _FakeActiveContextService(activeContext);
    final provider = ActiveContextProvider(service: service);
    final chatProvider = _FakeChatProvider();

    await tester.pumpWidget(
      _wrapWithApp(
        ActiveContextPanel(
          conversationId: 'c1',
          onRedirect: () {},
        ),
        contextProvider: provider,
        chatProvider: chatProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Database selection'), findsOneWidget);

    // Expand the item
    await tester.tap(find.text('Database selection'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('context_item_provenance_item-1')), findsOneWidget);
    expect(
      find.text('“We selected PostgreSQL for the application database.”'),
      findsOneWidget,
    );
    expect(find.textContaining('Source: Architecture chat'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);

    await tester.tap(find.text('Open source'));
    await tester.pumpAndSettle();
    expect(chatProvider.loadedConversationId, 'source-chat');
  });

  testWidgets('ActiveContextPanel adds a recent message through a source picker', (tester) async {
    final activeContext = ActiveContext(
      conversationId: 'c1',
      version: 4,
      readiness: ActiveContextReadiness.ready,
      items: const [],
    );
    final service = _FakeActiveContextService(activeContext);
    final provider = ActiveContextProvider(service: service);
    final chatProvider = _FakeChatProvider(
      messages: [
        ChatMessage(
          id: 'message-to-pin',
          role: 'user',
          content: 'Keep the deployment in the Virginia region.',
          createdAt: DateTime(2026, 9, 5),
        ),
      ],
    );

    await tester.pumpWidget(
      _wrapWithApp(
        ActiveContextPanel(conversationId: 'c1', onRedirect: () {}),
        contextProvider: provider,
        chatProvider: chatProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('context_add_source')));
    await tester.pumpAndSettle();

    expect(find.text('Choose a recent message'), findsOneWidget);
    expect(find.byKey(const ValueKey('context_source_message-to-pin')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('context_source_message-to-pin')));
    await tester.pumpAndSettle();
    expect(service.addedSourceId, 'message-to-pin');
  });

  testWidgets('TopicSwitchConfirmationDialog renders pinned-source retention option and confirm button', (tester) async {
    final targetTopic = TopicNode(
      id: 'target-topic',
      label: 'Target Project',
      origin: TopicOrigin.personal,
    );

    await tester.pumpWidget(
      _wrapWithApp(
        TopicSwitchConfirmationDialog(
          conversationId: 'c1',
          targetTopic: targetTopic,
        ),
        topicProvider: TopicDiscoveryProvider(service: _FakeTopicService([])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_switch_dialog')), findsOneWidget);
    expect(find.text('Target Project'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_switch_retain_pinned_checkbox')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_switch_confirm_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_switch_combine_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_switch_cancel_button')), findsOneWidget);
  });

  testWidgets('TopicSwitchConfirmationDialog combine button triggers combine action', (tester) async {
    const targetTopic = TopicNode(
      id: 'target-topic',
      label: 'Target Project',
      origin: TopicOrigin.personal,
    );

    final fakeService = _FakeTopicService([]);
    final topicProvider = TopicDiscoveryProvider(service: fakeService);

    await tester.pumpWidget(
      _wrapWithApp(
        TopicSwitchConfirmationDialog(
          conversationId: 'c1',
          targetTopic: targetTopic,
        ),
        topicProvider: topicProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('topic_switch_combine_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_switch_dialog')), findsNothing);
  });

  testWidgets('TopicContextEmptyState renders topic title, structured context, and starter chips', (tester) async {
    final activeContext = ActiveContext(
      conversationId: 'c1',
      version: 1,
      readiness: ActiveContextReadiness.ready,
      items: [
        ActiveContextItem(
          id: 'item-c1',
          sourceType: 'topic_assertion',
          sourceId: 'assertion-1',
          state: ActiveContextItemState.pinned,
          reason: 'Pinned by you',
          preview: 'Using PostgreSQL with pgvector',
        ),
      ],
      topic: null,
    );

    final contextProvider = ActiveContextProvider(
      service: _FakeActiveContextService(activeContext),
      topicService: _FakeTopicService([]),
    );
    await contextProvider.load('c1');

    final topic = TopicNode(
      id: 'ml-topic',
      label: 'Machine Learning',
      origin: TopicOrigin.personal,
      starterPrompts: ['Explain transformer attention mechanisms'],
    );

    String? sentPrompt;

    await tester.pumpWidget(
      _wrapWithApp(
        TopicContextEmptyState(
          conversationId: 'c1',
          topic: topic,
          onStarterSelected: (p) => sentPrompt = p,
        ),
        contextProvider: contextProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_context_empty_state')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_empty_state_title')), findsOneWidget);
    expect(find.text('Machine Learning'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_empty_state_context_card')), findsOneWidget);
    expect(find.text('STRUCTURED ACTIVE CONTEXT'), findsOneWidget);
    expect(find.text('1 pinned'), findsOneWidget);
    expect(find.text('Using PostgreSQL with pgvector'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_starter_chip_0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic_starter_chip_0')));
    expect(sentPrompt, 'Explain transformer attention mechanisms');
  });

  testWidgets('TopicBanner does not display preparingContext for TopicContextStatus.empty', (tester) async {
    final t1 = TopicNode(
      id: 'topic-clean',
      label: 'Fresh Topic',
      origin: TopicOrigin.personal,
      contextStatus: TopicContextStatus.empty,
    );
    final service = _FakeTopicService([t1]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.activate('c1', t1);

    await tester.pumpWidget(_wrapWithApp(const TopicBanner(), topicProvider: provider));
    await tester.pumpAndSettle();

    expect(find.text('Fresh Topic'), findsOneWidget);
    expect(find.text('Preparing context...'), findsNothing);
  });

  testWidgets('ActiveContextPanel renders Topic Context Tree, Lock Topic switch, and Switch Topic button', (tester) async {
    final rootTopic = TopicNode(
      id: 'parent-1',
      label: 'Parent Knowledge',
      origin: TopicOrigin.personal,
      children: const [
        TopicNode(
          id: 'child-1',
          label: 'Subtopic Alpha',
          origin: TopicOrigin.personal,
          parentId: 'parent-1',
        ),
      ],
    );
    final activeNode = TopicNode(
      id: 'topic-active',
      label: 'Deep Learning',
      parentId: 'parent-1',
      origin: TopicOrigin.personal,
      children: const [
        TopicNode(
          id: 'child-sub',
          label: 'Transformers',
          origin: TopicOrigin.personal,
        ),
      ],
    );
    final activeContext = ActiveContext(
      conversationId: 'c1',
      version: 2,
      readiness: ActiveContextReadiness.ready,
      topicPinned: true,
      topic: activeNode,
      items: const [],
      tokenCount: 200,
      tokenBudget: 4000,
    );

    final fakeContextService = _FakeActiveContextService(activeContext);
    final contextProvider = ActiveContextProvider(service: fakeContextService);
    final fakeTopicService = _FakeTopicService([rootTopic, activeNode]);
    final topicProvider = TopicDiscoveryProvider(service: fakeTopicService);
    await topicProvider.load();

    bool redirected = false;

    await tester.pumpWidget(
      _wrapWithApp(
        ActiveContextPanel(
          conversationId: 'c1',
          onRedirect: () => redirected = true,
        ),
        contextProvider: contextProvider,
        topicProvider: topicProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('active_context_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('context_topic_section')), findsOneWidget);
    expect(find.text('Deep Learning'), findsAtLeast(1));
    expect(find.byKey(const ValueKey('context_topic_pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('context_redirect')), findsOneWidget);
    expect(find.text('Parent Knowledge'), findsOneWidget);
    expect(find.text('Transformers'), findsOneWidget);

    // Tap switch topic
    await tester.tap(find.byKey(const ValueKey('context_redirect')));
    expect(redirected, isTrue);
  });

  testWidgets('ActiveContextPanel opens a read-only archived topic session', (tester) async {
    final archive = TopicArchive(
      id: 'archive-1',
      topicId: 'topic-active',
      fromTopicId: 'topic-active',
      conversationId: 'c1',
      messageCount: 2,
      createdAt: DateTime(2026, 9, 7, 14, 30),
    );
    final archivePage = TopicArchivePage(
      archive: archive,
      topicLabel: 'Deep Learning',
      sessionEpoch: 3,
      hasMore: false,
      messages: [
        ChatMessage(
          id: 'old-user',
          role: 'user',
          content: 'Explain the previous deployment decision.',
          createdAt: DateTime(2026, 9, 7, 14, 30),
        ),
        ChatMessage(
          id: 'old-assistant',
          role: 'assistant',
          content: 'The earlier session selected the Virginia region.',
          createdAt: DateTime(2026, 9, 7, 14, 31),
        ),
      ],
    );
    final activeContext = ActiveContext(
      conversationId: 'c1',
      version: 4,
      readiness: ActiveContextReadiness.ready,
      topic: const TopicNode(
        id: 'topic-active',
        label: 'Deep Learning',
        origin: TopicOrigin.personal,
      ),
      items: const [],
    );
    final contextProvider = ActiveContextProvider(
      service: _FakeActiveContextService(activeContext),
    );
    final topicProvider = TopicDiscoveryProvider(
      service: _FakeTopicService(
        const [],
        archives: [archive],
        archivePage: archivePage,
      ),
    );

    await tester.pumpWidget(
      _wrapWithApp(
        SizedBox(
          width: 304,
          child: ActiveContextPanel(
            conversationId: 'c1',
            onRedirect: () {},
          ),
        ),
        contextProvider: contextProvider,
        topicProvider: topicProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('context_view_archives')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic_archives_dialog')), findsOneWidget);
    expect(find.textContaining('2 messages'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic_archive_archive-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topic_archive_messages_dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('Read-only history'), findsOneWidget);
    expect(find.text('Explain the previous deployment decision.'), findsOneWidget);
    expect(
      find.text('The earlier session selected the Virginia region.'),
      findsOneWidget,
    );
  });

  testWidgets('ActiveContextPanel explains background preparation without a fake ETA', (tester) async {
    final activeNode = TopicNode(
      id: 'topic-nlp',
      label: 'Natural Language Processing',
      origin: TopicOrigin.personal,
    );
    final activeContext = ActiveContext(
      conversationId: 'c1',
      version: 1,
      readiness: ActiveContextReadiness.preparing,
      topicPinned: false,
      topic: activeNode,
      items: const [],
      tokenCount: 0,
      tokenBudget: 8000,
    );
    final fakeContextService = _FakeActiveContextService(activeContext);
    final contextProvider = ActiveContextProvider(service: fakeContextService);
    final fakeTopicService = _FakeTopicService([activeNode]);
    final topicProvider = TopicDiscoveryProvider(service: fakeTopicService);
    await topicProvider.load();

    await tester.pumpWidget(
      _wrapWithApp(
        ActiveContextPanel(
          conversationId: 'c1',
          onRedirect: () {},
        ),
        contextProvider: contextProvider,
        topicProvider: topicProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Context is updating in the background. Current valid sources remain available.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('<10s'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('TopicLanding keeps the primary conversation and uses the switch contract', (tester) async {
    final t1 = const TopicNode(id: 'topic-1', label: 'Machine Learning', origin: TopicOrigin.personal);
    final service = _FakeTopicService([t1]);
    final provider = TopicDiscoveryProvider(service: service);
    await provider.load();
    final fakeChat = _FakeChatProvider();

    await tester.pumpWidget(
      _wrapWithApp(
        TopicLanding(
          conversationId: 'primary',
          onStarterSelected: (_) {},
        ),
        topicProvider: provider,
        chatProvider: fakeChat,
      ),
    );
    await tester.pumpAndSettle();

    expect(provider.selectedTopic, isNull);
    await tester.tap(find.text('Machine Learning'));
    await tester.pumpAndSettle();

    // Verify dialog was NOT shown
    expect(find.byKey(const ValueKey('topic_switch_dialog')), findsNothing);
    // Verify topic selected
    expect(provider.selectedTopic?.id, 'topic-1');
    expect(fakeChat.createdConversations, isEmpty);
  });

  test('TopicGreetingData.tryParse extracts fields correctly from seeded greeting', () {
    const greeting = '''
### Topic: **Retirement planning**

*Financial planning for long-term retirement accounts and goals*

**Context included in this thread:**
• Maxing out 401(k) match is priority.
• Target retirement age is 62.

How can I help you with **Retirement planning** today?
''';

    final data = TopicGreetingData.tryParse(greeting);
    expect(data, isNotNull);
    expect(data!.topicLabel, 'Retirement planning');
    expect(data.topicDescription, 'Financial planning for long-term retirement accounts and goals');
    expect(data.sentences, ['Maxing out 401(k) match is priority.', 'Target retirement age is 62.']);
    expect(data.prompt, 'How can I help you with Retirement planning today?');
  });

  test('TopicGreetingData.tryParse returns null for regular markdown or user message', () {
    expect(TopicGreetingData.tryParse('Hello, how can you help me?'), isNull);
    expect(TopicGreetingData.tryParse('# Heading 1\nJust an ordinary message'), isNull);
  });

  testWidgets('ChatMessageWidget renders TopicGreetingCard for topic greeting message', (tester) async {
    const greeting = '''
### Topic: **Architecture**

*Software design and patterns*

**Context included in this thread:**
• Using PostgreSQL with pgvector
• Flutter client with Provider

How can I help you with **Architecture** today?
''';

    final message = ChatMessage(
      id: 'greeting-msg-1',
      role: 'assistant',
      content: greeting,
      createdAt: DateTime.now(),
    );

    bool openedContext = false;
    final settings = SettingsProvider();

    await tester.pumpWidget(
      _wrapWithApp(
        ChatMessageWidget(
          message: message,
          onOpenTopicContext: () => openedContext = true,
        ),
        settingsProvider: settings,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_greeting_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_greeting_title')), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
    expect(find.text('THREAD CONTEXT'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Software design and patterns'), findsOneWidget);
    expect(find.text('Using PostgreSQL with pgvector'), findsOneWidget);
    expect(find.text('Flutter client with Provider'), findsOneWidget);
    expect(find.text('How can I help you with Architecture today?'), findsOneWidget);

    // Verify assistant controls (regenerate, thumbs up, etc.) are NOT present
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);

    // Verify "View Details" triggers onOpenTopicContext
    expect(find.text('View Details'), findsOneWidget);
    await tester.tap(find.text('View Details'));
    expect(openedContext, isTrue);
  });

  testWidgets('ChatMessageWidget renders TopicGreetingCard with fallback description when sentences are empty', (tester) async {
    const greeting = '''
### Topic: **Retirement planning**

*Financial planning for long-term retirement accounts and goals*

This thread is focused on **Retirement planning**. New facts, decisions, and preferences will be remembered here as we chat.

How can I help you with **Retirement planning** today?
''';

    final message = ChatMessage(
      id: 'greeting-msg-2',
      role: 'assistant',
      content: greeting,
      createdAt: DateTime.now(),
    );

    final settings = SettingsProvider();

    await tester.pumpWidget(
      _wrapWithApp(
        ChatMessageWidget(message: message),
        settingsProvider: settings,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_greeting_card')), findsOneWidget);
    expect(find.text('Retirement planning'), findsOneWidget);
    expect(find.text('Financial planning for long-term retirement accounts and goals'), findsOneWidget);
    expect(find.textContaining('This thread is focused on Retirement planning'), findsOneWidget);
    expect(find.text('How can I help you with Retirement planning today?'), findsOneWidget);
  });

  testWidgets('TopicContextEmptyState uses fallback starters when starterPrompts is empty', (tester) async {
    final activeContext = ActiveContext(
      conversationId: 'c2',
      version: 1,
      readiness: ActiveContextReadiness.ready,
      items: const [],
      topic: null,
    );

    final contextProvider = ActiveContextProvider(
      service: _FakeActiveContextService(activeContext),
      topicService: _FakeTopicService([]),
    );
    await contextProvider.load('c2');

    final topic = TopicNode(
      id: 'fresh-topic',
      label: 'Home Renovation',
      origin: TopicOrigin.personal,
      starterPrompts: const [],
    );

    String? sentPrompt;

    await tester.pumpWidget(
      _wrapWithApp(
        TopicContextEmptyState(
          conversationId: 'c2',
          topic: topic,
          onStarterSelected: (p) => sentPrompt = p,
        ),
        contextProvider: contextProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic_context_empty_state')), findsOneWidget);
    expect(find.text('Home Renovation'), findsOneWidget);
    expect(find.text('Continue with Home Renovation'), findsOneWidget);
    expect(find.text('What should I do next about Home Renovation?'), findsOneWidget);
    expect(find.text('AVAILABLE TOPIC CONTEXT'), findsOneWidget);
    expect(
      find.text(
        'No established context is available for this topic yet. New decisions and preferences will appear here as you chat.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Clean session started'), findsNothing);

    await tester.tap(find.text('Continue with Home Renovation'));
    expect(sentPrompt, 'Continue with Home Renovation');
  });
}
