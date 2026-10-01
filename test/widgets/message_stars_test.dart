import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_message_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class _ReadAloud extends Mock implements ReadAloudController {}

class _Service extends ChatService {
  _Service(ChatMessage message) : super.forTesting() {
    conversation = Conversation(
      id: 'chat', model: 'test', createdAt: DateTime(2026),
      updatedAt: DateTime(2026), messages: [message],
    );
  }
  late Conversation conversation;
  Completer<bool>? pending;
  bool fail = false;
  int calls = 0;

  @override
  Future<ConversationList> listConversations({int page = 1, int pageSize = 20, bool silent = false}) async =>
      ConversationList(items: [conversation], total: 1, page: 1, pageSize: pageSize);

  @override
  Future<Conversation> getConversation(String id, {int? messageLimit, bool silent = false}) async => conversation;

  @override
  Future<bool> setMessageStar(String conversationId, String messageId, {required bool isStarred}) async {
    calls++;
    if (fail) throw StateError('save failed');
    final saved = pending == null ? isStarred : await pending!.future;
    conversation = conversation.copyWith(messages: [
      conversation.messages!.single.copyWith(isStarred: saved),
    ]);
    return saved;
  }
}

Future<ChatProvider> _mount(WidgetTester tester, _Service service, {
  String language = 'en', bool streaming = false,
}) async {
  final provider = ChatProvider(chatService: service);
  await provider.loadConversation('chat');
  addTearDown(provider.dispose);
  final readAloud = _ReadAloud();
  when(() => readAloud.active).thenReturn(false);
  when(() => readAloud.messageId).thenReturn(null);
  when(() => readAloud.state).thenReturn(ListeningState.idle);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ChatProvider>.value(value: provider),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ChangeNotifierProvider<ReadAloudController>.value(value: readAloud),
    ],
    child: MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Consumer<ChatProvider>(builder: (context, chat, _) =>
        ChatMessageWidget(message: chat.messages.single,
          conversationId: 'chat', isStreaming: streaming),
      )),
    ),
  ));
  await tester.pump();
  return provider;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('JSON defaults old messages to unstarred and reads canonical star state', () {
    final json = {'id': 'm', 'role': 'user', 'content': 'hello', 'created_at': '2026-01-01T00:00:00Z'};
    expect(ChatMessage.fromJson(json).isStarred, isFalse);
    expect(ChatMessage.fromJson({...json, 'is_starred': true}).isStarred, isTrue);
  });

  for (final role in ['user', 'assistant']) {
    testWidgets('$role star and unstar actions save and fit a phone', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _Service(ChatMessage(id: 'm', role: role, content: 'Useful message', createdAt: DateTime(2026)));
      final provider = await _mount(tester, service);
      final star = find.byKey(const ValueKey('star_message_m'));
      expect(find.text('Star message'), findsOneWidget);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(provider.messages.single.isStarred, isTrue);
      expect(find.text('Unstar message'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(provider.messages.single.isStarred, isFalse);
      expect(service.calls, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a pending save disables the action; failure remains visible in Spanish', (tester) async {
    final service = _Service(ChatMessage(id: 'm', role: 'user', content: 'Useful message', createdAt: DateTime(2026)))
      ..pending = Completer<bool>();
    final provider = await _mount(tester, service, language: 'es');
    final star = find.byKey(const ValueKey('star_message_m'));
    expect(find.text('Destacar mensaje'), findsOneWidget);
    await tester.tap(star);
    await tester.pump();
    expect(tester.widget<MessageActionButton>(star).onTap, isNull);
    service.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Quitar destacado'), findsOneWidget);
    service.fail = true;
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(provider.messages.single.isStarred, isTrue);
    expect(find.text('No se pudo actualizar el destacado del mensaje. Inténtalo de nuevo.'), findsOneWidget);
  });

  for (final state in ['temporary', 'streaming']) {
    testWidgets('$state messages do not offer starring', (tester) async {
      final service = _Service(ChatMessage(id: state == 'temporary' ? 'temp-m' : 'm',
        role: 'assistant', content: 'Still writing', createdAt: DateTime(2026)));
      await _mount(tester, service, streaming: state == 'streaming');
      expect(find.text('Star message'), findsNothing);
      expect(service.calls, 0);
    });
  }
}
