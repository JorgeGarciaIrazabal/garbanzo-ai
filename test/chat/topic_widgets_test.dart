import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
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
  _FakeChatProvider({List<ChatMessage> messages = const []}) : _initialMessages = messages;

  final List<ChatMessage> _initialMessages;
  final List<Map<String, dynamic>> createdConversations = [];

  @override
  List<ChatMessage> get messages => _initialMessages;

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
}

class _FakeTopicService extends TopicService {
  _FakeTopicService(this.topics) : super.forTesting();
  final List<TopicNode> topics;

  @override
  Future<List<TopicNode>> listTopics(TopicOrigin mode) async => topics;

  @override
  Future<void> activateTopic(
    String conversationId, {
    String? topicId,
    String? label,
  }) async {}

  @override
  Future<void> prepare(String topicId) async {}

  @override
  Future<TopicSwitchResponse> switchTopic(
    String conversationId, {
    String? topicId,
    String? label,
    bool archive = true,
    int carryoverMaxItems = 5,
    int carryoverMaxTokens = 400,
    String mode = 'switch',
  }) async =>
      TopicSwitchResponse(
        conversationId: conversationId,
        contextVersion: 2,
        archived: archive,
        carryover: const [],
      );
}

class _FakeActiveContextService extends ActiveContextService {
  _FakeActiveContextService(this.activeContext) : super.forTesting();
  final ActiveContext activeContext;

  @override
  Future<ActiveContext> getContext(String conversationId) async => activeContext;
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

  testWidgets('ActiveContextPanel displays evidence provenance chip', (tester) async {
    final item = ActiveContextItem(
      id: 'item-1',
      sourceType: 'message',
      sourceId: 'msg-123456789',
      state: ActiveContextItemState.dynamic,
      reason: 'Explicit user statement in turn',
      title: 'Database selection',
      preview: 'PostgreSQL database',
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

    await tester.pumpWidget(
      _wrapWithApp(
        ActiveContextPanel(
          conversationId: 'c1',
          onRedirect: () {},
        ),
        contextProvider: provider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Database selection'), findsOneWidget);

    // Expand the item
    await tester.tap(find.text('Database selection'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('context_item_provenance_item-1')), findsOneWidget);
    expect(find.textContaining('Source: message #msg-1234'), findsOneWidget);
  });

  testWidgets('TopicSwitchConfirmationDialog renders carryover option and confirm button', (tester) async {
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
    expect(find.byKey(const ValueKey('topic_switch_carryover_checkbox')), findsOneWidget);
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
          sourceType: 'carryover',
          sourceId: 'msg-prev',
          state: ActiveContextItemState.dynamic,
          reason: 'carryover decision',
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
    expect(find.text('1 carried over'), findsOneWidget);
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

  testWidgets('ActiveContextPanel renders animated multi-stage preparing banner when readiness is preparing', (tester) async {
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
    await tester.pump();

    expect(find.text('Preparing the best context'), findsOneWidget);
    expect(find.textContaining('<10s'), findsOneWidget);
    expect(find.text('Scanning topic assertions & evidence...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });

  testWidgets('TopicLanding onStart creates dedicated thread with activeTopicId when ChatProvider is present', (tester) async {
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
    // Verify thread creation was triggered with activeTopicId and topic label
    expect(fakeChat.createdConversations, hasLength(1));
    expect(fakeChat.createdConversations.first['title'], 'Machine Learning');
    expect(fakeChat.createdConversations.first['activeTopicId'], 'topic-1');
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

    await tester.tap(find.text('Continue with Home Renovation'));
    expect(sentPrompt, 'Continue with Home Renovation');
  });
}
