import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_message_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/thinking_content.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class _MockChatProvider extends Mock implements ChatProvider {}

Widget _wrap(ChatMessage message) {
  final chat = _MockChatProvider();
  when(() => chat.isSending).thenReturn(false);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
      ChangeNotifierProvider<ChatProvider>.value(
        value: chat,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatMessageWidget(message: message),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatMessageWidget thinking separation', () {
    testWidgets(
      'separates <think>...</think> from message content when metadata is missing thinking',
      (tester) async {
        final message = ChatMessage(
          id: 'msg-1',
          role: 'assistant',
          content:
              '<think>The user is asking who Clara is again.</think>Clara is your daughter!',
          createdAt: DateTime(2026, 9, 5),
        );

        await tester.pumpWidget(_wrap(message));
        await tester.pumpAndSettle();

        // Thinking component should be rendered
        expect(find.byType(ThinkingContent), findsOneWidget);
        expect(find.text('Show thinking'), findsOneWidget);

        // Message content should only contain the clean answer
        expect(find.text('Clara is your daughter!'), findsOneWidget);
        expect(
          find.text(
            '<think>The user is asking who Clara is again.</think>Clara is your daughter!',
          ),
          findsNothing,
        );

        // Expanding thinking reveals the reasoning text
        await tester.tap(find.text('Show thinking'));
        await tester.pumpAndSettle();
        expect(
          find.text('The user is asking who Clara is again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'handles leaked </think> without opening <think> tag gracefully',
      (tester) async {
        final message = ChatMessage(
          id: 'msg-2',
          role: 'assistant',
          content:
              'Analyzing past conversations.</think>She is enrolled in art class.',
          createdAt: DateTime(2026, 9, 5),
        );

        await tester.pumpWidget(_wrap(message));
        await tester.pumpAndSettle();

        expect(find.byType(ThinkingContent), findsOneWidget);
        expect(find.text('She is enrolled in art class.'), findsOneWidget);

        await tester.tap(find.text('Show thinking'));
        await tester.pumpAndSettle();
        expect(find.text('Analyzing past conversations.'), findsOneWidget);
      },
    );

    testWidgets(
      'uses metadata thinking when present without double rendering',
      (tester) async {
        final message = ChatMessage(
          id: 'msg-3',
          role: 'assistant',
          content: 'Here is the answer.',
          metadata: {'thinking': 'Pre-parsed reasoning'},
          createdAt: DateTime(2026, 9, 5),
        );

        await tester.pumpWidget(_wrap(message));
        await tester.pumpAndSettle();

        expect(find.byType(ThinkingContent), findsOneWidget);
        expect(find.text('Here is the answer.'), findsOneWidget);

        await tester.tap(find.text('Show thinking'));
        await tester.pumpAndSettle();
        expect(find.text('Pre-parsed reasoning'), findsOneWidget);
      },
    );
  });
}
