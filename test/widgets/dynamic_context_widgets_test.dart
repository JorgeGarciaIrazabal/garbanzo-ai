import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/services/active_context_service.dart';
import 'package:garbanzo_ai/features/topics/services/topic_service.dart';
import 'package:garbanzo_ai/features/topics/widgets/active_context_panel.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_sidebar.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_drawer.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_field.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_landing.dart';
import 'package:garbanzo_ai/features/chat/widgets/topic_banner.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';

class _ContextService extends ActiveContextService {
  _ContextService(this.value) : super.forTesting();

  final ActiveContext value;

  @override
  Future<ActiveContext> getContext(String conversationId) async => value;
}

class _TopicService extends TopicService {
  _TopicService(this.personalTopics) : super.forTesting();

  final List<TopicNode> personalTopics;
  final List<String> activatedTopicIds = [];

  @override
  Future<List<TopicNode>> listTopics(TopicOrigin mode) async =>
      mode == TopicOrigin.personal ? personalTopics : const [];

  @override
  Future<void> activateTopic(
    String conversationId, {
    String? topicId,
    String? label,
  }) async {
    if (topicId != null) activatedTopicIds.add(topicId);
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
    if (topicId != null) activatedTopicIds.add(topicId);
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
  Future<void> prepare(String topicId) async {}
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  final topics = [
    const TopicNode(
      id: 'finance',
      label: 'Finance',
      origin: TopicOrigin.history,
      childCount: 1,
    ),
    const TopicNode(
      id: 'travel',
      label: 'Travel',
      origin: TopicOrigin.history,
    ),
  ];

  testWidgets('topic field is vertical at 320px and horizontal on tablet/desktop', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 320,
          child: TopicField(
            topics: topics,
            parentLabel: 'Personal finance',
            onStart: (_) {},
            onOpenChildren: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('topic_field_vertical')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_field_horizontal')), findsNothing);
    expect(find.text('Subtopic in Personal finance'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 768,
          child: TopicField(
            topics: topics,
            onStart: (_) {},
            onOpenChildren: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('topic_field_horizontal')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_field_vertical')), findsNothing);
    final financePosition = tester.getTopLeft(
      find.byKey(const ValueKey('topic_button_finance')),
    );
    final travelPosition = tester.getTopLeft(
      find.byKey(const ValueKey('topic_button_travel')),
    );
    expect(financePosition.dy, isNot(travelPosition.dy));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 1200,
          child: TopicField(
            topics: topics,
            onStart: (_) {},
            onOpenChildren: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('topic_field_horizontal')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'importance materially scales gradient nodes and phone promotes three ranked subtopics',
    (tester) async {
      const finance = TopicNode(
        id: 'finance-high',
        label: 'Finance',
        origin: TopicOrigin.history,
        score: 0.96,
        childCount: 2,
        children: [
          TopicNode(
            id: 'retirement-high',
            parentId: 'finance-high',
            label: 'Retirement',
            origin: TopicOrigin.history,
            score: 0.92,
          ),
          TopicNode(
            id: 'taxes-medium',
            parentId: 'finance-high',
            label: 'Quarterly taxes',
            origin: TopicOrigin.history,
            score: 0.71,
          ),
        ],
      );
      const travel = TopicNode(
        id: 'travel-low',
        label: 'Travel someday',
        origin: TopicOrigin.history,
        score: 0.18,
        childCount: 2,
        children: [
          TopicNode(
            id: 'japan-high',
            parentId: 'travel-low',
            label: 'Japan trip',
            origin: TopicOrigin.history,
            score: 0.86,
          ),
          TopicNode(
            id: 'weekend-low',
            parentId: 'travel-low',
            label: 'Weekend away',
            origin: TopicOrigin.suggested,
            score: 0.22,
          ),
        ],
      );

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 390,
            child: TopicField(
              topics: const [finance, travel],
              onStart: (_) {},
              onOpenChildren: (_) {},
            ),
          ),
        ),
      );

      final highSize = tester.getSize(
        find.byKey(const ValueKey('topic_surface_finance-high')),
      );
      final lowSize = tester.getSize(
        find.byKey(const ValueKey('topic_surface_travel-low')),
      );
      expect(highSize.width, equals(lowSize.width));
      expect(highSize.height, greaterThan(lowSize.height));

      expect(
        find.byKey(const ValueKey('subtopic_marker_retirement-high')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subtopic_marker_japan-high')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subtopic_marker_taxes-medium')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subtopic_marker_weekend-low')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('irrelevant subtopics stay hidden behind their parent', (
    tester,
  ) async {
    const parent = TopicNode(
      id: 'travel-low',
      label: 'Travel someday',
      origin: TopicOrigin.history,
      score: 0.2,
      childCount: 2,
      children: [
        TopicNode(
          id: 'japan-mid',
          parentId: 'travel-low',
          label: 'Japan trip',
          origin: TopicOrigin.history,
          score: 0.48,
        ),
        TopicNode(
          id: 'weekend-low',
          parentId: 'travel-low',
          label: 'Weekend away',
          origin: TopicOrigin.suggested,
          score: 0.22,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 390,
          child: TopicField(
            topics: const [parent],
            onStart: (_) {},
            onOpenChildren: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('subtopic_marker_japan-mid')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subtopic_marker_weekend-low')),
      findsNothing,
    );
    expect(find.text('Travel someday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tapping a parent drills into subtopics and leaf children start directly',
    (tester) async {
      final retirement = TopicNode(
        id: 'retirement',
        label: 'Retirement',
        origin: TopicOrigin.personal,
        childCount: 2,
        children: const [
          TopicNode(
            id: '401k',
            parentId: 'retirement',
            label: '401(k) contributions',
            origin: TopicOrigin.personal,
            score: 0.9,
          ),
          TopicNode(
            id: 'ira',
            parentId: 'retirement',
            label: 'Roth IRA',
            origin: TopicOrigin.personal,
            score: 0.8,
          ),
        ],
      );
      final started = <String>[];
      final opened = <String>[];

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 390,
            child: TopicField(
              topics: [retirement],
              onStart: (topic) => started.add(topic.id),
              onOpenChildren: (topic) => opened.add(topic.id),
            ),
          ),
        ),
      );

      expect(find.text('Subtopic in Retirement'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('topic_button_retirement')));
      expect(opened, ['retirement']);
      await tester.tap(find.byKey(const ValueKey('topic_button_401k')));
      expect(started, ['401k']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parent with only 1 subtopic does not promote it and starts parent directly on first click',
    (tester) async {
      final housing = TopicNode(
        id: 'housing',
        label: 'Housing',
        origin: TopicOrigin.personal,
        childCount: 1,
        children: const [
          TopicNode(
            id: 'selling',
            parentId: 'housing',
            label: 'Selling',
            origin: TopicOrigin.personal,
            score: 0.9,
          ),
        ],
      );
      final started = <String>[];
      final opened = <String>[];

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 390,
            child: TopicField(
              topics: [housing],
              onStart: (topic) => started.add(topic.id),
              onOpenChildren: (topic) => opened.add(topic.id),
            ),
          ),
        ),
      );

      // Subtopic is not promoted or shown as separate button or meta badge
      expect(find.text('Subtopic in Housing'), findsNothing);
      expect(find.text('1 subtopic'), findsNothing);
      expect(find.byKey(const ValueKey('topic_button_selling')), findsNothing);

      // First click on parent directly starts it without opening children
      await tester.tap(find.byKey(const ValueKey('topic_button_housing')));
      expect(opened, isEmpty);
      expect(started, ['housing']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('landing is fully replaced by chat after selecting a topic', (
    tester,
  ) async {
    final selected = TopicNode(
      id: 'retirement',
      label: 'Retirement',
      origin: TopicOrigin.personal,
    );
    final service = _TopicService([selected]);
    final provider = TopicDiscoveryProvider(service: service);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: _app(
          Builder(
            builder: (context) => context.watch<TopicDiscoveryProvider>().showLanding
                ? const TopicLanding(
                    conversationId: 'primary',
                    onStarterSelected: _discardString,
                  )
                : const TextField(key: ValueKey('chat_composer_after_topic')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('topic_landing')), findsOneWidget);
    expect(find.text('What should we continue?'), findsNothing);
    expect(
      find.text(
        'Your topics are shaped by recent conversations, open loops, and what matters now.',
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('topic_button_retirement')));
    await tester.pump();

    expect(service.activatedTopicIds, ['retirement']);
    expect(find.byKey(const ValueKey('topic_landing')), findsNothing);
    expect(find.byKey(const ValueKey('chat_composer_after_topic')), findsOneWidget);
  });

  testWidgets('landing renders mockup chrome: mode pills, atmosphere, breadcrumbs', (
    tester,
  ) async {
    final parent = TopicNode(
      id: 'finance',
      label: 'Finance',
      origin: TopicOrigin.personal,
      childCount: 2,
      children: const [
        TopicNode(
          id: '401k',
          parentId: 'finance',
          label: '401(k) contributions',
          origin: TopicOrigin.personal,
          score: 0.9,
        ),
        TopicNode(
          id: 'savings',
          parentId: 'finance',
          label: 'Savings',
          origin: TopicOrigin.personal,
          score: 0.8,
        ),
      ],
    );
    final provider = TopicDiscoveryProvider(
      service: _TopicService([parent]),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: _app(
          SizedBox(
            width: 1000,
            child: TopicLanding(
              conversationId: 'primary',
              onStarterSelected: _discardString,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('topic_mode_selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_mode_personal')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic_mode_explore')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic_mode_explore')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('something_new_topic')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('topic_mode_personal')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Browse Finance subtopics'));
    await tester.pump();

    expect(find.byKey(const ValueKey('topic_breadcrumbs')), findsOneWidget);
    expect(find.text('All topics'), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('401(k) contributions'), findsOneWidget);
  });

  testWidgets('active context is explainable and contains no Activity view', (
    tester,
  ) async {
    final active = ActiveContext(
      conversationId: 'primary',
      version: 1,
      readiness: ActiveContextReadiness.ready,
      topic: topics.first,
      tokenCount: 40,
      tokenBudget: 100,
      summary: 'Finance goal and current constraints.',
      items: const [
        ActiveContextItem(
          id: 'pin',
          sourceType: 'memory',
          sourceId: 'm1',
          state: ActiveContextItemState.pinned,
          reason: 'Pinned by you',
          title: 'Risk preference',
        ),
        ActiveContextItem(
          id: 'dynamic',
          sourceType: 'message',
          sourceId: 'msg1',
          state: ActiveContextItemState.dynamic,
          reason: 'Recent topic evidence',
          title: 'Contribution decision',
        ),
      ],
    );
    final provider = ActiveContextProvider(service: _ContextService(active));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: _app(
          const SizedBox(
            height: 700,
            child: ActiveContextPanel(
              conversationId: 'primary',
              onRedirect: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('active_context_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('context_branch_memory')), findsOneWidget);
    expect(find.byKey(const ValueKey('context_branch_message')), findsOneWidget);
    expect(find.text('Next-turn preview'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('context_item_pin')));
    await tester.pump();
    expect(find.text('Why included: Pinned by you'), findsOneWidget);
  });

  testWidgets('topics sidebar provides its own Material surface for tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TopicDiscoveryProvider()),
          ChangeNotifierProvider(create: (_) => RoomProvider()),
          ChangeNotifierProvider(create: (_) => SearchProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            height: 700,
            child: ChatSidebar(
              conversations: const [],
              selectedConversationId: null,
              onSelectConversation: _discardString,
              onDeleteConversation: _discardString,
              onNewChat: _noop,
              onTogglePin: _discardString,
              isLoadingConversations: false,
              onSelectRoom: _discardString,
              onDeleteRoom: _discardString,
              onOpenPrimary: _noop,
              initialTab: 0,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chat_sidebar_material')), findsOneWidget);
  });

  testWidgets('sidebar navigation keeps Topics and legacy Threads distinct', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TopicDiscoveryProvider()),
          ChangeNotifierProvider(create: (_) => RoomProvider()),
          ChangeNotifierProvider(create: (_) => SearchProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            height: 700,
            child: ChatSidebar(
              conversations: const [],
              selectedConversationId: null,
              onSelectConversation: _discardString,
              onDeleteConversation: _discardString,
              onNewChat: _noop,
              onTogglePin: _discardString,
              isLoadingConversations: false,
              onSelectRoom: _discardString,
              onDeleteRoom: _discardString,
              onOpenPrimary: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('sidebar_tab_topics')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_tab_threads')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_tab_rooms')), findsOneWidget);
    expect(find.text('New thread'), findsOneWidget);
    expect(find.byKey(const ValueKey('new_topic_sidebar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sidebar_tab_topics')));
    await tester.pump();
    expect(find.byKey(const ValueKey('new_topic_sidebar')), findsOneWidget);
    expect(find.text('New thread'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sidebar_tab_threads')));
    await tester.pump();
    expect(find.text('New thread'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile drawer exposes the same reachable Topics and Threads tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TopicDiscoveryProvider()),
          ChangeNotifierProvider(create: (_) => RoomProvider()),
          ChangeNotifierProvider(create: (_) => SearchProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showMobileConversationDrawer(
                    context: context,
                    conversations: const [],
                    selectedId: null,
                    onSelect: _discardString,
                    onDelete: _discardString,
                    onNewChat: _noop,
                    initialTab: 1,
                  ),
                  child: const Text('Open navigation'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open navigation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_drawer_tab_threads')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_new_thread')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_drawer_tab_topics')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mobile_new_topic')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic banner surfaces selected topic and preparing state', (
    tester,
  ) async {
    const topic = TopicNode(
      id: 'finance',
      label: 'Finance',
      origin: TopicOrigin.history,
    );
    final provider = TopicDiscoveryProvider(service: _TopicService([topic]));
    await provider.activate('primary', topic);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: _app(
          const SizedBox(
            height: 200,
            child: TopicBanner(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('topic_banner')), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);
  });
}

void _noop() {}

void _discardString(String _) {}
