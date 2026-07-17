import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_editor_dialog.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_banner.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:provider/provider.dart';

/// Minimal fake ChatProvider that only exposes what SystemPromptBanner reads.
class _FakeChatProvider extends ChatProvider {
  _FakeChatProvider(this._conversation);

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

class _FakeModelProvider extends ModelProvider {
  _FakeModelProvider(this._selectedModelId);
  final String? _selectedModelId;

  @override
  String? get selectedModelId => _selectedModelId;

  @override
  List<ModelInfo> get availableModels => const [];
}

/// The template dropdown reads the builtin/custom getters, not `templates`,
/// so the picker tests need a fake that overrides those directly.
class _FakeTemplateProvider extends SystemPromptProvider {
  _FakeTemplateProvider({
    List<SystemPromptTemplate> builtins = const [],
    List<SystemPromptTemplate> customs = const [],
  }) : _builtins = builtins,
       _customs = customs;

  final List<SystemPromptTemplate> _builtins;
  List<SystemPromptTemplate> _customs;

  @override
  List<SystemPromptTemplate> get builtinTemplates => _builtins;

  @override
  List<SystemPromptTemplate> get customTemplates => _customs;

  @override
  bool get isLoading => false;

  @override
  Future<bool> deleteTemplate(String id) async {
    _customs = _customs.where((t) => t.id != id).toList();
    notifyListeners();
    return true;
  }

  @override
  Future<SystemPromptTemplate?> updateTemplate(
    String templateId, {
    String? name,
    String? content,
    String? description,
  }) async {
    _customs = _customs
        .map(
          (t) => t.id == templateId
              ? t.copyWith(
                  name: name ?? t.name,
                  content: content ?? t.content,
                  description: description,
                )
              : t,
        )
        .toList();
    notifyListeners();
    return _customs.firstWhere((t) => t.id == templateId);
  }
}

SystemPromptTemplate _template(String id, String name, {bool builtin = false}) =>
    SystemPromptTemplate(
      id: id,
      name: name,
      content: 'content of $name',
      isBuiltin: builtin,
      createdAt: DateTime(2026),
    );

Future<void> _openEditor(WidgetTester tester, SystemPromptProvider p) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SystemPromptProvider>.value(value: p),
          ChangeNotifierProvider<ModelProvider>.value(
            value: _FakeModelProvider('test-model'),
          ),
        ],
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SystemPromptEditorDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

  group('SystemPromptEditorDialog.show', () {
    testWidgets('reaches a route-scoped provider from the dialog route',
        (tester) async {
      // Mirrors the real app: the provider lives inside a route (ChatPage /
      // SettingsPage subtree), below the Navigator. The dialog opens on its
      // own route, so it can only see the provider if show() re-exposes it.
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SystemPromptProvider>.value(
                value: _FakeSystemPromptProvider(null, const []),
              ),
              ChangeNotifierProvider<ModelProvider>.value(
                value: _FakeModelProvider('test-model'),
              ),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SystemPromptEditorDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      // Fixed pumps instead of pumpAndSettle: the template list may show a
      // perpetual loading spinner while the fake provider's refresh hangs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Edit system prompt'), findsOneWidget);
    });

    testWidgets('shows "Create with AI" button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SystemPromptProvider>.value(
                value: _FakeSystemPromptProvider(null, const []),
              ),
              ChangeNotifierProvider<ModelProvider>.value(
                value: _FakeModelProvider('test-model'),
              ),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SystemPromptEditorDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Create with AI'), findsOneWidget);
    });

    testWidgets('tapping "Create with AI" opens the generation panel',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SystemPromptProvider>.value(
                value: _FakeSystemPromptProvider(null, const []),
              ),
              ChangeNotifierProvider<ModelProvider>.value(
                value: _FakeModelProvider('test-model'),
              ),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SystemPromptEditorDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Create with AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Describe what you want the prompt to do:'),
        findsOneWidget,
      );
      expect(find.text('Generate'), findsOneWidget);
    });
  });

  group('SystemPromptEditorDialog template picker', () {
    testWidgets('builds and selects with both builtin and custom templates', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _FakeTemplateProvider(
          builtins: [_template('b1', 'Builtin One', builtin: true)],
          customs: [_template('c1', 'Custom One')],
        ),
      );
      expect(tester.takeException(), isNull, reason: 'dialog build');

      await tester.tap(find.text('— None —'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'opening the menu');

      await tester.tap(find.text('Builtin One').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'selecting a template');
      expect(find.text('content of Builtin One'), findsOneWidget);
    });

    testWidgets('deleting the selected custom template resets to none', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _FakeTemplateProvider(customs: [_template('c1', 'Custom One')]),
      );

      await tester.tap(find.text('— None —'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom One').last);
      await tester.pumpAndSettle();

      // The delete affordance only appears for a selected custom template.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'after delete');
      expect(find.text('— None —'), findsOneWidget);
    });

    testWidgets('editing the selected custom template updates the editor', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _FakeTemplateProvider(customs: [_template('c1', 'Custom One')]),
      );

      await tester.tap(find.text('— None —'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom One').last);
      await tester.pumpAndSettle();

      // The edit affordance only appears for a selected custom template.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Edit "Custom One"'), findsOneWidget);

      // Fields are pre-seeded from the saved template; the main editor holds
      // the same text, so take the dialog's (topmost) field.
      await tester.enterText(
        find.widgetWithText(TextField, 'content of Custom One').last,
        'sharper content',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'after edit');
      // The applied template follows the edit into the main editor.
      expect(find.text('sharper content'), findsOneWidget);
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
