import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/mute_util.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/conversation_list_controller.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/conversation_list_widget.dart';

final _now = DateTime.utc(2026, 7, 15);

/// The far-future value the backend stores for "muted forever"
/// (`mute_util.MUTE_FOREVER`).
final _foreverSentinel = DateTime.utc(9999, 12, 31, 23, 59, 59);

Conversation _conversation({
  String id = 'c1',
  String title = 'Convo One',
  DateTime? mutedUntil,
}) => Conversation(
  id: id,
  title: title,
  model: 'llama3.2',
  createdAt: _now,
  updatedAt: _now,
  mutedUntil: mutedUntil,
);

/// Records `setMute` calls and returns a scripted response; other methods
/// used by [ConversationListController]/[ChatProvider] delegate to an
/// in-memory conversation list so `load()` reflects `setMute`'s effect.
class _FakeChatService extends ChatService {
  _FakeChatService() : super.forTesting();

  final Map<String, Conversation> conversationsById = {'c1': _conversation()};

  final List<(String, String)> setMuteCalls = [];
  Exception? setMuteError;

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 20,
  }) async {
    final items = conversationsById.values.toList();
    return ConversationList(
      items: items,
      total: items.length,
      page: 1,
      pageSize: 20,
    );
  }

  @override
  Future<Conversation> setMute(String conversationId, String duration) async {
    setMuteCalls.add((conversationId, duration));
    if (setMuteError != null) throw setMuteError!;
    final mutedUntil = switch (duration) {
      'unmute' => null,
      'forever' => _foreverSentinel,
      _ => DateTime.now().toUtc().add(const Duration(hours: 8)),
    };
    final updated = conversationsById[conversationId]!.copyWith(
      mutedUntil: mutedUntil,
    );
    conversationsById[conversationId] = updated;
    return updated;
  }

  @override
  Future<Conversation> getConversation(String conversationId) async =>
      conversationsById[conversationId]!;

  @override
  Future<void> stopStreaming(String conversationId) async {}

  @override
  Future<void> deleteConversation(String conversationId) async {}
}

void main() {
  group('Conversation mute state', () {
    test('a null muted_until is not muted', () {
      expect(_conversation().isMuted, isFalse);
      expect(isMuteActive(null), isFalse);
    });

    test('an expired muted_until is not muted', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(_conversation(mutedUntil: past).isMuted, isFalse);
    });

    test('a future muted_until is muted', () {
      final future = DateTime.now().add(const Duration(hours: 8));
      expect(_conversation(mutedUntil: future).isMuted, isTrue);
    });

    test('the year-9999 sentinel is muted, and muted forever', () {
      final c = _conversation(mutedUntil: _foreverSentinel);
      expect(c.isMuted, isTrue);
      expect(c.isMutedForever, isTrue);
    });

    test('a timed mute is not a forever mute', () {
      final c = _conversation(
        mutedUntil: DateTime.now().add(const Duration(days: 7)),
      );
      expect(c.isMuted, isTrue);
      expect(c.isMutedForever, isFalse);
    });

    test('fromJson maps muted_until, tolerating its absence', () {
      Conversation parse(Map<String, dynamic> extra) =>
          Conversation.fromJson({
            'id': 'c1',
            'title': 'Convo',
            'model': 'llama3.2',
            'created_at': _now.toIso8601String(),
            'updated_at': _now.toIso8601String(),
            ...extra,
          });

      expect(parse(const {}).mutedUntil, isNull);
      expect(parse(const {'muted_until': null}).mutedUntil, isNull);
      expect(
        parse({
          'muted_until': _foreverSentinel.toIso8601String(),
        }).isMutedForever,
        isTrue,
      );
    });

    test('toJson round-trips muted_until', () {
      final c = _conversation(mutedUntil: _foreverSentinel);
      final json = c.toJson();
      expect(json['muted_until'], _foreverSentinel.toIso8601String());
    });
  });

  group('ConversationListController.setMute', () {
    test(
      'adopts the server-returned expiry and replaces the listed entry',
      () async {
        final service = _FakeChatService();
        final controller = ConversationListController(chatService: service);
        await controller.load();
        expect(controller.conversations.single.isMuted, isFalse);

        var notified = 0;
        controller.addListener(() => notified++);

        final updated = await controller.setMute('c1', muteDuration8h);

        expect(service.setMuteCalls, [('c1', '8h')]);
        expect(updated?.isMuted, isTrue);
        expect(controller.conversations.single.isMuted, isTrue);
        expect(notified, greaterThan(0));
      },
    );

    test('unmute clears the listed entry', () async {
      final service = _FakeChatService();
      final controller = ConversationListController(chatService: service);
      await controller.load();

      await controller.setMute('c1', muteDurationForever);
      expect(controller.conversations.single.isMuted, isTrue);

      await controller.setMute('c1', muteDurationUnmute);
      expect(controller.conversations.single.isMuted, isFalse);
      expect(controller.conversations.single.mutedUntil, isNull);
    });

    test('a failing request surfaces the error and returns null', () async {
      final service = _FakeChatService()
        ..setMuteError = Exception('boom');
      final controller = ConversationListController(chatService: service);
      await controller.load();

      final result = await controller.setMute('c1', muteDuration8h);

      expect(result, isNull);
      expect(controller.error, contains('boom'));
      expect(controller.conversations.single.isMuted, isFalse);
    });
  });

  group('ChatProvider.setMute', () {
    test('syncs the currently-open conversation with the server response', () async {
      final service = _FakeChatService();
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );
      await provider.loadConversation('c1');
      expect(provider.currentConversation?.isMuted, isFalse);

      await provider.setMute('c1', muteDuration8h);

      expect(provider.currentConversation?.isMuted, isTrue);
      expect(provider.conversations.first.isMuted, isTrue);
    });

    test('leaves an unrelated open conversation untouched', () async {
      final service = _FakeChatService();
      service.conversationsById['c2'] = _conversation(id: 'c2', title: 'Two');
      final provider = ChatProvider(
        selectedModelId: 'llama3.2',
        chatService: service,
      );
      await provider.loadConversation('c2');

      await provider.setMute('c1', muteDuration8h);

      expect(provider.currentConversation?.id, 'c2');
      expect(provider.currentConversation?.isMuted, isFalse);
    });
  });

  group('mute sheet (ConversationListWidget)', () {
    Widget host(
      List<Conversation> conversations, {
      void Function(Conversation, String)? onMute,
    }) => ChangeNotifierProvider<SearchProvider>(
      create: (_) => SearchProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: ConversationListWidget(
            conversations: conversations,
            selectedId: null,
            onSelect: (_) {},
            onDelete: (_) {},
            onNewChat: () {},
            onMute: onMute,
            embedded: true,
          ),
        ),
      ),
    );

    testWidgets('long-press opens the sheet and the choice calls back', (
      tester,
    ) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        host([_conversation()], onMute: (c, d) => calls.add((c.id, d))),
      );

      await tester.longPress(find.text('Convo One'));
      await tester.pumpAndSettle();

      expect(find.text('8 hours'), findsOneWidget);
      expect(find.text('1 week'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
      expect(find.text('Unmute'), findsNothing);

      await tester.tap(find.text('8 hours'));
      await tester.pumpAndSettle();

      expect(calls, [('c1', '8h')]);
    });

    testWidgets('a muted conversation offers unmute and shows its status', (
      tester,
    ) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        host(
          [_conversation(mutedUntil: _foreverSentinel)],
          onMute: (c, d) => calls.add((c.id, d)),
        ),
      );

      expect(
        find.byKey(const ValueKey('conversation_muted_glyph')),
        findsOneWidget,
      );

      await tester.longPress(find.text('Convo One'));
      await tester.pumpAndSettle();

      expect(find.text('Muted always'), findsOneWidget);
      expect(find.textContaining('9999'), findsNothing);
      expect(find.text('Unmute'), findsOneWidget);

      await tester.tap(find.text('Unmute'));
      await tester.pumpAndSettle();

      expect(calls, [('c1', 'unmute')]);
    });

    testWidgets('an unmuted conversation shows no bell glyph', (tester) async {
      await tester.pumpWidget(host([_conversation()]));
      expect(
        find.byKey(const ValueKey('conversation_muted_glyph')),
        findsNothing,
      );
    });

    testWidgets('an expired mute shows no bell glyph', (tester) async {
      await tester.pumpWidget(
        host([
          _conversation(
            mutedUntil: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ]),
      );
      expect(
        find.byKey(const ValueKey('conversation_muted_glyph')),
        findsNothing,
      );
    });

    testWidgets('without onMute, long-press does nothing', (tester) async {
      await tester.pumpWidget(host([_conversation()]));

      await tester.longPress(find.text('Convo One'));
      await tester.pumpAndSettle();

      expect(find.text('8 hours'), findsNothing);
    });
  });
}
