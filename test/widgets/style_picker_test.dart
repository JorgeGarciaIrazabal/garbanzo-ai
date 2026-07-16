import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/style_picker.dart';
import 'package:provider/provider.dart';

// ============================================================================
// Fakes — each overrides exactly what the picker actually reads/calls, so a
// widget reading something else fails loudly instead of passing vacuously
// (the 8131cdf lesson).
// ============================================================================

class _FakeChatProvider extends ChatProvider {
  _FakeChatProvider({Conversation? conversation, bool sending = false})
    : _conversation = conversation,
      _sending = sending;

  Conversation? _conversation;
  final bool _sending;

  /// Recorded named arguments of every updateConversation call.
  final List<Map<String, Object?>> updates = [];

  @override
  Conversation? get currentConversation => _conversation;

  @override
  bool get isSending => _sending;

  @override
  Future<void> updateConversation({
    String? title,
    String? model,
    bool? useMemory,
    bool? useKnowledgeBase,
    String? systemPrompt,
    bool clearSystemPrompt = false,
    List<String>? enabledTools,
    bool clearEnabledTools = false,
    bool? isPinned,
    ThinkingLevel? thinkingLevel,
    bool setThinkingLevel = false,
  }) async {
    updates.add({
      'model': model,
      'systemPrompt': systemPrompt,
      'clearSystemPrompt': clearSystemPrompt,
      'thinkingLevel': thinkingLevel,
      'setThinkingLevel': setThinkingLevel,
    });
    _conversation = _conversation?.copyWith(
      model: model ?? _conversation!.model,
      systemPrompt: clearSystemPrompt
          ? null
          : (systemPrompt ?? _conversation!.systemPrompt),
      thinkingLevel: setThinkingLevel
          ? thinkingLevel
          : _conversation!.thinkingLevel,
    );
    notifyListeners();
  }
}

class _FakeModelProvider extends ModelProvider {
  _FakeModelProvider({required List<ModelInfo> models, String? selectedId})
    : _models = models,
      _selectedId = selectedId;

  final List<ModelInfo> _models;
  String? _selectedId;
  final List<String> selections = [];
  final List<String?> persistedDefaults = [];

  @override
  List<ModelInfo> get availableModels => List.unmodifiable(_models);

  @override
  String? get selectedModelId => _selectedId;

  @override
  void selectModel(String modelId) {
    selections.add(modelId);
    if (_models.any((m) => m.id == modelId)) {
      _selectedId = modelId;
      notifyListeners();
    }
  }

  @override
  Future<bool> setDefaultModel(String? modelId) async {
    persistedDefaults.add(modelId);
    return true;
  }
}

class _FakeStyleProvider extends StyleProvider {
  _FakeStyleProvider({List<Style> styles = const []}) : _fakeStyles = styles;

  List<Style> _fakeStyles;
  final List<Map<String, Object?>> created = [];

  @override
  List<Style> get styles => List.unmodifiable(_fakeStyles);

  @override
  bool get isLoading => false;

  @override
  Future<Style?> createStyle({
    required String name,
    required String modelId,
    ThinkingLevel? thinkingLevel,
    String? systemPromptTemplateId,
    bool isDefault = false,
  }) async {
    created.add({
      'name': name,
      'modelId': modelId,
      'thinkingLevel': thinkingLevel,
      'systemPromptTemplateId': systemPromptTemplateId,
      'isDefault': isDefault,
    });
    final style = Style(
      id: 'new-${created.length}',
      name: name,
      modelId: modelId,
      thinkingLevel: thinkingLevel,
      systemPromptTemplateId: systemPromptTemplateId,
      isDefault: isDefault,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    _fakeStyles = [..._fakeStyles, style];
    notifyListeners();
    return style;
  }

  @override
  Future<bool> deleteStyle(String styleId) async {
    _fakeStyles = _fakeStyles.where((s) => s.id != styleId).toList();
    notifyListeners();
    return true;
  }
}

class _FakeSystemPromptProvider extends SystemPromptProvider {
  _FakeSystemPromptProvider({List<SystemPromptTemplate> templates = const []})
    : _fakeTemplates = templates;

  final List<SystemPromptTemplate> _fakeTemplates;

  @override
  List<SystemPromptTemplate> get templates =>
      List.unmodifiable(_fakeTemplates);

  @override
  bool get isLoading => false;
}

// ============================================================================
// Fixtures
// ============================================================================

ModelInfo _model(
  String id, {
  bool? thinking,
  bool? tools,
  bool? vision,
  String? description,
}) => ModelInfo(
  id: id,
  name: id,
  provider: 'ollama',
  description: description,
  supportsThinking: thinking,
  supportsTools: tools,
  supportsVision: vision,
);

Style _style(
  String id,
  String name, {
  String modelId = 'qwen3',
  ThinkingLevel? thinkingLevel,
  String? templateId,
  bool isDefault = false,
}) => Style(
  id: id,
  name: name,
  modelId: modelId,
  thinkingLevel: thinkingLevel,
  systemPromptTemplateId: templateId,
  isDefault: isDefault,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

SystemPromptTemplate _template(String id, String name) => SystemPromptTemplate(
  id: id,
  name: name,
  content: 'content of $name',
  createdAt: DateTime(2026),
);

Conversation _conversation({
  String model = 'qwen3',
  String? systemPrompt,
  ThinkingLevel? thinkingLevel,
}) => Conversation(
  id: 'c1',
  title: 'Test',
  model: model,
  systemPrompt: systemPrompt,
  thinkingLevel: thinkingLevel,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _defaultModels = [
  _model('qwen3', thinking: true, tools: true, vision: false),
  _model('llama3.2', tools: true),
  _model('gemma3-vision', vision: true, description: 'sees images'),
];

// ============================================================================
// Harness
// ============================================================================

Widget _wrap({
  required _FakeChatProvider chat,
  required _FakeModelProvider models,
  required _FakeStyleProvider styles,
  required _FakeSystemPromptProvider prompts,
}) {
  // Providers live below the navigator like on the real chat page, so these
  // tests exercise showStylePicker's provider re-exposure across routes.
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<ModelProvider>.value(value: models),
        ChangeNotifierProvider<StyleProvider>.value(value: styles),
        ChangeNotifierProvider<SystemPromptProvider>.value(value: prompts),
      ],
      child: const Scaffold(
        appBar: null,
        body: Align(
          alignment: Alignment.topRight,
          child: StylePickerButton(),
        ),
      ),
    ),
  );
}

void _setScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// [testWidgets] wrapper that settles after the body: the real provider
/// constructors (which the fakes extend) fire guarded network attempts whose
/// zero-duration dio timers would otherwise still be pending at teardown.
void _testPicker(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpAndSettle();
  });
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('style_picker_button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('StylePickerButton', () {
    _testPicker('shows the effective model name without exceptions', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: _defaultModels,
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('qwen3'), findsOneWidget);
    });

    _testPicker('prefers the active conversation model over the selection', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(conversation: _conversation(model: 'llama3.2')),
          models: _FakeModelProvider(
            models: _defaultModels,
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      expect(find.text('llama3.2'), findsOneWidget);
      expect(find.text('qwen3'), findsNothing);
    });

    _testPicker('hides when there are no models', (tester) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(models: const []),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('style_picker_button')), findsNothing);
    });
  });

  group('StylePicker panel (mobile bottom sheet)', () {
    _testPicker('opens with saved style cards and no exceptions', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: _defaultModels,
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(
            styles: [
              _style('s1', 'Deep work', thinkingLevel: ThinkingLevel.high),
              _style('s2', 'Quick answers', modelId: 'llama3.2'),
            ],
          ),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      expect(tester.takeException(), isNull, reason: 'panel build');
      expect(find.text('Chat style'), findsOneWidget);
      expect(find.text('Deep work'), findsOneWidget);
      expect(find.text('Quick answers'), findsOneWidget);
      // With saved styles present, Customize starts collapsed.
      expect(find.byKey(const ValueKey('style_search_field')), findsNothing);
    });

    _testPicker('applying a style updates conversation, model, and pendings', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      final chat = _FakeChatProvider(conversation: _conversation());
      final models = _FakeModelProvider(
        models: _defaultModels,
        selectedId: 'qwen3',
      );
      final styles = _FakeStyleProvider(
        styles: [
          _style(
            's1',
            'Deep work',
            modelId: 'llama3.2',
            thinkingLevel: ThinkingLevel.high,
            templateId: 't1',
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          chat: chat,
          models: models,
          styles: styles,
          prompts: _FakeSystemPromptProvider(
            templates: [_template('t1', 'Architect')],
          ),
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.text('Deep work'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(models.selections, ['llama3.2']);
      expect(styles.pendingThinkingLevel, ThinkingLevel.high);
      expect(styles.pendingSystemPrompt, 'content of Architect');
      expect(chat.updates, hasLength(1));
      expect(chat.updates.single['model'], 'llama3.2');
      expect(chat.updates.single['thinkingLevel'], ThinkingLevel.high);
      expect(chat.updates.single['setThinkingLevel'], true);
      expect(chat.updates.single['systemPrompt'], 'content of Architect');
      // Applying closes the sheet.
      expect(find.text('Chat style'), findsNothing);
    });

    _testPicker('a style whose model is missing warns instead of applying', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      final chat = _FakeChatProvider(conversation: _conversation());
      final models = _FakeModelProvider(
        models: _defaultModels,
        selectedId: 'qwen3',
      );
      await tester.pumpWidget(
        _wrap(
          chat: chat,
          models: models,
          styles: _FakeStyleProvider(
            styles: [_style('s1', 'Gone', modelId: 'uninstalled:7b')],
          ),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.text('Gone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(chat.updates, isEmpty);
      expect(models.selections, isEmpty);
      expect(find.text('uninstalled:7b is not installed'), findsOneWidget);
    });

    _testPicker(
      'customize: search filters models and capability badges show',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _wrap(
            chat: _FakeChatProvider(),
            models: _FakeModelProvider(
              models: _defaultModels,
              selectedId: 'qwen3',
            ),
            // No saved styles: Customize starts expanded.
            styles: _FakeStyleProvider(),
            prompts: _FakeSystemPromptProvider(),
          ),
        );
        await _openPicker(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('style_search_field')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('model_row_qwen3')), findsOneWidget);
        // qwen3 advertises thinking+tools; gemma3-vision advertises vision.
        expect(find.byIcon(Icons.psychology_outlined), findsWidgets);
        expect(find.byIcon(Icons.build_outlined), findsWidgets);
        expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('style_search_field')),
          'vision',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byKey(const ValueKey('model_row_gemma3-vision')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('model_row_qwen3')), findsNothing);
        expect(find.byKey(const ValueKey('model_row_llama3.2')), findsNothing);
      },
    );

    _testPicker('selecting a model applies it to the active conversation', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      final chat = _FakeChatProvider(conversation: _conversation());
      final models = _FakeModelProvider(
        models: _defaultModels,
        selectedId: 'qwen3',
      );
      await tester.pumpWidget(
        _wrap(
          chat: chat,
          models: models,
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.byKey(const ValueKey('model_row_llama3.2')));
      await tester.pump();

      expect(models.selections, ['llama3.2']);
      expect(chat.updates.single['model'], 'llama3.2');
      // Panel stays open for further composing.
      expect(find.text('Chat style'), findsOneWidget);
    });

    _testPicker('thinking control sets the level and pends it', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      final chat = _FakeChatProvider(conversation: _conversation());
      final styles = _FakeStyleProvider();
      await tester.pumpWidget(
        _wrap(
          chat: chat,
          models: _FakeModelProvider(
            models: _defaultModels,
            selectedId: 'qwen3',
          ),
          styles: styles,
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('thinking_segment')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('High'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(styles.pendingThinkingLevel, ThinkingLevel.high);
      expect(chat.updates.single['thinkingLevel'], ThinkingLevel.high);
      expect(chat.updates.single['setThinkingLevel'], true);
    });

    _testPicker('thinking control is disabled for non-thinking models', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          // llama3.2 has supportsThinking == null->false? (unset). Use a
          // conversation pinned to a model that reports thinking: false.
          chat: _FakeChatProvider(
            conversation: _conversation(model: 'no-think'),
          ),
          models: _FakeModelProvider(
            models: [_model('no-think', thinking: false)],
            selectedId: 'no-think',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('thinking_segment')),
      );
      await tester.pumpAndSettle();

      final highChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'High'),
      );
      expect(highChip.onSelected, isNull);
      expect(find.text('Not supported by this model'), findsOneWidget);
    });

    _testPicker(
      'template dropdown survives a conversation prompt whose template '
      'was deleted (8131cdf regression)',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        // The conversation prompt matches no surviving template.
        final chat = _FakeChatProvider(
          conversation: _conversation(systemPrompt: 'content of Deleted'),
        );
        await tester.pumpWidget(
          _wrap(
            chat: chat,
            models: _FakeModelProvider(
              models: _defaultModels,
              selectedId: 'qwen3',
            ),
            styles: _FakeStyleProvider(),
            prompts: _FakeSystemPromptProvider(
              templates: [_template('t1', 'Architect')],
            ),
          ),
        );
        await _openPicker(tester);

        expect(tester.takeException(), isNull, reason: 'panel build');
        await tester.ensureVisible(
          find.byKey(const ValueKey('template_dropdown')),
        );
        await tester.pump();
        // Falls back to the sentinel and flags the custom prompt.
        expect(find.text('No template'), findsOneWidget);
        expect(
          find.textContaining('custom prompt'),
          findsOneWidget,
        );
      },
    );

    _testPicker('picking a template applies its content', (tester) async {
      _setScreenSize(tester, const Size(390, 844));
      final chat = _FakeChatProvider(conversation: _conversation());
      final styles = _FakeStyleProvider();
      await tester.pumpWidget(
        _wrap(
          chat: chat,
          models: _FakeModelProvider(
            models: _defaultModels,
            selectedId: 'qwen3',
          ),
          styles: styles,
          prompts: _FakeSystemPromptProvider(
            templates: [_template('t1', 'Architect')],
          ),
        ),
      );
      await _openPicker(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('template_dropdown')),
      );
      await tester.pump();
      await tester.tap(find.text('No template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Architect').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(styles.pendingSystemPrompt, 'content of Architect');
      expect(chat.updates.single['systemPrompt'], 'content of Architect');
      expect(chat.updates.single['clearSystemPrompt'], false);
    });

    _testPicker('save style composes the current selection', (tester) async {
      _setScreenSize(tester, const Size(390, 844));
      final styles = _FakeStyleProvider();
      final models = _FakeModelProvider(
        models: _defaultModels,
        selectedId: 'qwen3',
      );
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: models,
          styles: styles,
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      // Compose: thinking high (no conversation, so it only pends).
      await tester.ensureVisible(
        find.byKey(const ValueKey('thinking_segment')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('High'));
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey('save_style_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save_style_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(
        find.byKey(const ValueKey('style_name_field')),
        'Deep work',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save_style_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(styles.created, hasLength(1));
      expect(styles.created.single['name'], 'Deep work');
      expect(styles.created.single['modelId'], 'qwen3');
      expect(styles.created.single['thinkingLevel'], ThinkingLevel.high);
      expect(styles.created.single['isDefault'], false);
      // The new style now renders as a card.
      expect(find.byKey(const ValueKey('style_card_new-1')), findsOneWidget);
    });
  });

  group('StylePicker panel (desktop popover)', () {
    _testPicker('opens as an anchored popover without exceptions', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: _defaultModels,
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(styles: [_style('s1', 'Deep work')]),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Chat style'), findsOneWidget);
      expect(find.text('Deep work'), findsOneWidget);
      // Popovers get an explicit close affordance (sheets have drag handles).
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Chat style'), findsNothing);
    });
  });

  group('ChatProvider pending style state', () {
    test('new conversations are created with pending thinking and prompt',
        () async {
      final service = _RecordingChatService();
      final chat = ChatProvider(
        selectedModelId: 'qwen3',
        chatService: service,
      );
      chat.pendingThinkingLevel = ThinkingLevel.high;
      chat.pendingSystemPrompt = 'be brief';

      await chat.sendMessage('hello');

      expect(service.createArgs, isNotNull);
      expect(service.createArgs!['model'], 'qwen3');
      expect(service.createArgs!['thinkingLevel'], ThinkingLevel.high);
      expect(service.createArgs!['systemPrompt'], 'be brief');
    });
  });
}

class _RecordingChatService extends ChatService {
  _RecordingChatService() : super.forTesting();

  Map<String, Object?>? createArgs;

  @override
  Future<Conversation> createConversation({
    String? title,
    String model = 'llama3.2',
    String? initialMessage,
    String? systemPrompt,
    ThinkingLevel? thinkingLevel,
  }) async {
    createArgs = {
      'model': model,
      'systemPrompt': systemPrompt,
      'thinkingLevel': thinkingLevel,
    };
    return Conversation(
      id: 'c1',
      title: title,
      model: model,
      systemPrompt: systemPrompt,
      thinkingLevel: thinkingLevel,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<Conversation> getConversation(String conversationId) async =>
      _conversation(model: createArgs?['model'] as String? ?? 'qwen3');

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 20,
  }) async =>
      const ConversationList(items: [], total: 0, page: 1, pageSize: 20);

  @override
  Stream<ChatResponseChunk> streamChatResponse(
    String conversationId,
    String message, {
    List<ChatAttachment> attachments = const [],
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
  }) =>
      Stream.fromIterable([const ChatResponseChunk(type: 'done')]);
}
