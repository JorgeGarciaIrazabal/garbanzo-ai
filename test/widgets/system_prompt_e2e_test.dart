import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_editor_dialog.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_banner.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:provider/provider.dart';

/// Minimal fake ChatProvider that only exposes what SystemPromptBanner reads.
class _FakeChatProvider extends ChatProvider {
  _FakeChatProvider(this._conversation) : super(selectedModelId: () => null);

  final Conversation? _conversation;

  @override
  Conversation? get currentConversation => _conversation;
}

class _FakeSystemPromptProvider extends SystemPromptProvider {
  _FakeSystemPromptProvider(this._userDefault, this._templates);
  final String? _userDefault;
  final List<SystemPromptTemplate> _templates;

  @override
  String? get userDefault => _userDefault;

  @override
  List<SystemPromptTemplate> get templates => List.unmodifiable(_templates);
}

void main() {
  group('SystemPromptEditorResult semantics', () {
    test('default constructor → cancelled', () {
      const r = SystemPromptEditorResult();
      expect(r.isCancelled, isTrue);
      expect(r.isClear, isFalse);
      expect(r.content, isNull);
    });

    test('empty content → clear', () {
      const r = SystemPromptEditorResult(content: '');
      expect(r.isClear, isTrue);
      expect(r.isCancelled, isFalse);
    });

    test('non-empty content → apply', () {
      const r = SystemPromptEditorResult(content: 'hello');
      expect(r.isClear, isFalse);
      expect(r.isCancelled, isFalse);
      expect(r.content, 'hello');
    });
  });

  group('SystemPromptBanner', () {
    Widget wrap({
      Conversation? conversation,
      String? userDefault,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(
            value: _FakeChatProvider(conversation),
          ),
          ChangeNotifierProvider<SystemPromptProvider>.value(
            value: _FakeSystemPromptProvider(userDefault, const []),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SystemPromptBanner()),
        ),
      );
    }

    testWidgets('shows "Conversation override" label when conv has prompt',
        (tester) async {
      final conv = Conversation(
        id: 'c1',
        title: 'Test',
        model: 'test',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        messageCount: 0,
        useMemory: true,
        systemPrompt: 'Be a pirate.',
      );
      await tester.pumpWidget(wrap(conversation: conv, userDefault: 'global'));
      expect(find.text('System prompt'), findsOneWidget);
      expect(find.text('Conversation override'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('shows "Global default" when no conv prompt, has user default',
        (tester) async {
      final conv = Conversation(
        id: 'c1',
        title: 'Test',
        model: 'test',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        messageCount: 0,
        useMemory: true,
      );
      await tester
          .pumpWidget(wrap(conversation: conv, userDefault: 'global default'));
      expect(find.text('Global default'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('shows "No system prompt" when nothing is set',
        (tester) async {
      final conv = Conversation(
        id: 'c1',
        title: 'Test',
        model: 'test',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        messageCount: 0,
        useMemory: true,
      );
      await tester.pumpWidget(wrap(conversation: conv));
      expect(find.text('No system prompt'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('hides entirely when no current conversation', (tester) async {
      await tester.pumpWidget(wrap(conversation: null));
      expect(find.text('System prompt'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('expanding shows the active prompt text', (tester) async {
      final conv = Conversation(
        id: 'c1',
        title: 'Test',
        model: 'test',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        messageCount: 0,
        useMemory: true,
        systemPrompt: 'Be concise.',
      );
      await tester.pumpWidget(wrap(conversation: conv));
      await tester.tap(find.text('System prompt'));
      await tester.pumpAndSettle();
      expect(find.text('Be concise.'), findsOneWidget);
    });
  });
}
