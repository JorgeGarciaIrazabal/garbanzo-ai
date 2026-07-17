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
import 'package:garbanzo_ai/features/chat/services/style_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/style_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

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
  final List<Map<String, Object?>> updated = [];

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

  @override
  Future<Style?> updateStyle(
    String styleId, {
    String? name,
    String? modelId,
    ThinkingLevel? thinkingLevel,
    bool setThinkingLevel = false,
    String? systemPromptTemplateId,
    bool setTemplateId = false,
    bool? isDefault,
  }) async {
    updated.add({
      'styleId': styleId,
      'name': name,
      'modelId': modelId,
      'thinkingLevel': thinkingLevel,
      'setThinkingLevel': setThinkingLevel,
      'systemPromptTemplateId': systemPromptTemplateId,
      'setTemplateId': setTemplateId,
      'isDefault': isDefault,
    });
    _fakeStyles = _fakeStyles
        .map(
          (s) => s.id == styleId
              ? s.copyWith(
                  name: name ?? s.name,
                  modelId: modelId ?? s.modelId,
                  thinkingLevel: setThinkingLevel
                      ? thinkingLevel
                      : s.thinkingLevel,
                  systemPromptTemplateId: setTemplateId
                      ? systemPromptTemplateId
                      : s.systemPromptTemplateId,
                  isDefault: isDefault ?? s.isDefault,
                )
              : s,
        )
        .toList();
    notifyListeners();
    return _fakeStyles.firstWhere((s) => s.id == styleId);
  }
}

/// Fake [StyleService] for exercising the real [StyleProvider] (not the
/// picker-facing [_FakeStyleProvider] above) so the last-used/default
/// seeding logic in `_seedPendingFromDefault` runs against canned data
/// instead of a live backend.
class _FakeStyleService extends StyleService {
  _FakeStyleService(this._styles) : super.forTesting();

  final List<Style> _styles;

  @override
  Future<List<Style>> listStyles() async => _styles;
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
    
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
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

/// Finds a capability badge inside one model row. The filter chips use the
/// same icons by design, so a bare `byIcon` would also match the control above
/// the list and say nothing about what the row shows.
Finder _badge(String modelId, IconData icon) => find.descendant(
  of: find.byKey(ValueKey('model_row_$modelId')),
  matching: find.byIcon(icon),
);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('style_picker_button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Polls until a [StyleProvider]'s constructor-triggered `refresh()` (and
/// the seeding it does once styles load) has settled.
Future<void> _waitForLoad(StyleProvider provider) async {
  while (provider.isLoading) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // recordLastUsed / the real StyleProvider's last-used seeding both read
    // SharedPreferences; mock it so every test (not just the persistence
    // group below) gets a clean in-memory store instead of a missing-plugin
    // exception.
    SharedPreferences.setMockInitialValues({});
  });

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

    _testPicker(
      'shows the style name (not the model) when the conversation matches '
      'a saved style',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _wrap(
            chat: _FakeChatProvider(
              conversation: _conversation(
                model: 'llama3.2',
                thinkingLevel: ThinkingLevel.high,
              ),
            ),
            models: _FakeModelProvider(
              models: _defaultModels,
              selectedId: 'qwen3',
            ),
            styles: _FakeStyleProvider(
              styles: [
                _style(
                  's1',
                  'Deep work',
                  modelId: 'llama3.2',
                  thinkingLevel: ThinkingLevel.high,
                ),
              ],
            ),
            prompts: _FakeSystemPromptProvider(),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Deep work'), findsOneWidget);
        expect(find.text('llama3.2'), findsNothing);
        // Monogram avatar in place of the plain sparkle icon.
        expect(find.text('D'), findsOneWidget);
        expect(find.byIcon(Icons.auto_awesome), findsNothing);
      },
    );

    _testPicker(
      'falls back to the model name when settings match no saved style',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _wrap(
            chat: _FakeChatProvider(
              conversation: _conversation(model: 'llama3.2'),
            ),
            models: _FakeModelProvider(
              models: _defaultModels,
              selectedId: 'qwen3',
            ),
            // Same style, but a different thinking level than the
            // conversation's — no match.
            styles: _FakeStyleProvider(
              styles: [
                _style(
                  's1',
                  'Deep work',
                  modelId: 'llama3.2',
                  thinkingLevel: ThinkingLevel.high,
                ),
              ],
            ),
            prompts: _FakeSystemPromptProvider(),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('llama3.2'), findsOneWidget);
        expect(find.text('Deep work'), findsNothing);
        expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      },
    );

    _testPicker(
      'matches a style whose prompt template resolves to the conversation '
      'prompt content',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _wrap(
            chat: _FakeChatProvider(
              conversation: _conversation(
                model: 'qwen3',
                systemPrompt: 'content of Architect',
              ),
            ),
            models: _FakeModelProvider(
              models: _defaultModels,
              selectedId: 'qwen3',
            ),
            styles: _FakeStyleProvider(
              styles: [_style('s1', 'Architect mode', templateId: 't1')],
            ),
            prompts: _FakeSystemPromptProvider(
              templates: [_template('t1', 'Architect')],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Architect mode'), findsOneWidget);
      },
    );

    _testPicker(
      'outside a conversation, matches against the pending thinking/prompt '
      'the picker composed',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        final styles = _FakeStyleProvider(
          styles: [
            _style(
              's1',
              'Deep work',
              modelId: 'qwen3',
              thinkingLevel: ThinkingLevel.high,
            ),
          ],
        );
        // No active conversation: pending state (as the picker would set
        // via setPendingThinkingLevel) stands in for the conversation's.
        styles.setPendingThinkingLevel(ThinkingLevel.high);
        await tester.pumpWidget(
          _wrap(
            chat: _FakeChatProvider(),
            models: _FakeModelProvider(
              models: _defaultModels,
              selectedId: 'qwen3',
            ),
            styles: styles,
            prompts: _FakeSystemPromptProvider(),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Deep work'), findsOneWidget);
      },
    );
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
      // With saved styles present, the Styles section is the visible one.
      expect(find.byKey(const ValueKey('style_search_field')), findsNothing);
    });

    _testPicker(
      'with no saved styles, starts on Customize and the Styles section '
      'offers a compose shortcut',
      (tester) async {
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
        await _openPicker(tester);

        // No saved styles: composing is the only thing to do, so the
        // Customize section is the visible one.
        expect(
          find.byKey(const ValueKey('style_search_field')),
          findsOneWidget,
        );

        // The Styles section explains itself and links back to Customize.
        await tester.tap(find.text('Styles'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('style_search_field')), findsNothing);
        expect(find.textContaining('No saved styles yet'), findsOneWidget);

        await tester.tap(find.text('Compose a style'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('style_search_field')),
          findsOneWidget,
        );
      },
    );

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
      // Persisted so it can seed pendings on the next app start too.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('style_last_used_style_id'), 's1');
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
      // Bailing out before applying must not record the style as last-used.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('style_last_used_style_id'), isNull);
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
            // No saved styles: the Customize section is the visible one.
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
        expect(_badge('qwen3', Icons.psychology_outlined), findsOneWidget);
        expect(_badge('qwen3', Icons.build_outlined), findsOneWidget);
        expect(_badge('gemma3-vision', Icons.visibility_outlined),
            findsOneWidget);
        // Reported false / unreported earns no badge.
        expect(_badge('qwen3', Icons.visibility_outlined), findsNothing);
        expect(_badge('llama3.2', Icons.psychology_outlined), findsNothing);

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

    _testPicker('capability filter narrows the list to matching models', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: [
              _model('qwen3', thinking: true, tools: true, vision: false),
              _model('llama3.2', tools: true, vision: false),
              _model('gemma3-vision', vision: true, tools: false),
            ],
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);
      expect(tester.takeException(), isNull, reason: 'panel build');

      await tester.tap(find.byKey(const ValueKey('capability_filter_vision')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('model_row_gemma3-vision')),
        findsOneWidget,
      );
      // Both explicitly report vision: false.
      expect(find.byKey(const ValueKey('model_row_qwen3')), findsNothing);
      expect(find.byKey(const ValueKey('model_row_llama3.2')), findsNothing);
    });

    _testPicker('multiple capability filters must all match', (tester) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: [
              _model('qwen3', thinking: true, tools: true, vision: false),
              _model('llama3.2', thinking: false, tools: true, vision: false),
            ],
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.byKey(const ValueKey('capability_filter_tools')));
      await tester.pump();
      // Tools alone keeps both.
      expect(find.byKey(const ValueKey('model_row_qwen3')), findsOneWidget);
      expect(find.byKey(const ValueKey('model_row_llama3.2')), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('capability_filter_thinking')),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('model_row_qwen3')), findsOneWidget);
      expect(find.byKey(const ValueKey('model_row_llama3.2')), findsNothing);

      // Toggling off restores it.
      await tester.tap(
        find.byKey(const ValueKey('capability_filter_thinking')),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('model_row_llama3.2')), findsOneWidget);
    });

    _testPicker('capability filter composes with the text search', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: [
              _model('qwen3-vl', tools: true, vision: true),
              _model('qwen3', tools: true, vision: false),
              _model('gemma3-vision', tools: false, vision: true),
            ],
            selectedId: 'qwen3',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.byKey(const ValueKey('capability_filter_vision')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('style_search_field')),
        'qwen',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Only the model passing BOTH the query and the filter survives.
      expect(find.byKey(const ValueKey('model_row_qwen3-vl')), findsOneWidget);
      // Matches the query but not the filter.
      expect(find.byKey(const ValueKey('model_row_qwen3')), findsNothing);
      // Matches the filter but not the query.
      expect(
        find.byKey(const ValueKey('model_row_gemma3-vision')),
        findsNothing,
      );
    });

    _testPicker(
      'a model with an unknown capability is kept under that filter and '
      'marked, not silently hidden',
      (tester) async {
        _setScreenSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          _wrap(
            chat: _FakeChatProvider(),
            models: _FakeModelProvider(
              // cloud-model reports nothing; no-vision explicitly says no.
              models: [
                _model('cloud-model'),
                _model('no-vision', vision: false),
                _model('sees', vision: true),
              ],
              selectedId: 'sees',
            ),
            styles: _FakeStyleProvider(),
            prompts: _FakeSystemPromptProvider(),
          ),
        );
        await _openPicker(tester);

        // No filter yet: an unknown flag earns no badge at all.
        expect(_badge('cloud-model', Icons.visibility_outlined), findsNothing);
        expect(_badge('sees', Icons.visibility_outlined), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('capability_filter_vision')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('model_row_sees')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('model_row_cloud-model')),
          findsOneWidget,
          reason: 'unknown != false; a failed lookup must not hide a model',
        );
        expect(find.byKey(const ValueKey('model_row_no-vision')), findsNothing);
        // The kept unknown is marked so the row does not read as a confirmed
        // vision model, and the marker is visibly weaker than a real badge.
        expect(
          _badge('cloud-model', Icons.visibility_outlined),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Vision unknown for this model'),
          findsOneWidget,
        );
        final unknown = tester.widget<Icon>(
          _badge('cloud-model', Icons.visibility_outlined),
        );
        final confirmed = tester.widget<Icon>(
          _badge('sees', Icons.visibility_outlined),
        );
        expect(unknown.color!.a, lessThan(confirmed.color!.a));
      },
    );

    _testPicker('the empty state names the filter, not the search', (
      tester,
    ) async {
      _setScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: [_model('no-vision', vision: false, tools: true)],
            selectedId: 'no-vision',
          ),
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.byKey(const ValueKey('capability_filter_vision')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text('No models have the selected capabilities.'),
        findsOneWidget,
      );
      expect(find.text('No models match your search.'), findsNothing);

      // With both narrowing, the copy accounts for both.
      await tester.enterText(
        find.byKey(const ValueKey('style_search_field')),
        'zzz',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('No models match your search and the selected capabilities.'),
        findsOneWidget,
      );

      // Search alone keeps the original copy.
      await tester.tap(find.byKey(const ValueKey('capability_filter_vision')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No models match your search.'), findsOneWidget);
    });

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

    _testPicker('editing a saved style updates it without touching the chat', (
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
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          chat: chat,
          models: models,
          styles: styles,
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('style_card_s1')),
          matching: find.byTooltip('Style options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit…'));
      await tester.pumpAndSettle();

      // The picker switches to the Customize section in edit mode, seeded
      // from the style.
      expect(find.text('Editing "Deep work"'), findsOneWidget);

      // Recomposing the model only changes the edit state, not the live chat.
      await tester.ensureVisible(find.byKey(const ValueKey('model_row_qwen3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model_row_qwen3')));
      await tester.pump();
      expect(models.selections, isEmpty);
      expect(chat.updates, isEmpty);

      await tester.ensureVisible(
        find.byKey(const ValueKey('save_style_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save_style_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The dialog is the edit variant, pre-filled with the style's name.
      expect(find.text('Edit style'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save_style_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(styles.created, isEmpty);
      expect(styles.updated, hasLength(1));
      final u = styles.updated.single;
      expect(u['styleId'], 's1');
      expect(u['name'], 'Deep work');
      expect(u['modelId'], 'qwen3');
      expect(u['thinkingLevel'], ThinkingLevel.high);
      expect(u['setThinkingLevel'], true);
      // Edit mode ends after saving.
      expect(find.text('Editing "Deep work"'), findsNothing);
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
      // The style's settings match the effective (no-conversation) state, so
      // it shows twice: once as the pill label, once as its card in the
      // panel below.
      expect(find.text('Deep work'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('style_card_s1')), findsOneWidget);
      // Popovers get an explicit close affordance (sheets have drag handles).
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Chat style'), findsNothing);
    });

    _testPicker('capability filter works in the popover too', (tester) async {
      _setScreenSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        _wrap(
          chat: _FakeChatProvider(),
          models: _FakeModelProvider(
            models: [
              _model('qwen3', tools: true, vision: false),
              _model('gemma3-vision', vision: true),
            ],
            selectedId: 'qwen3',
          ),
          // No saved styles: the Customize section is the visible one.
          styles: _FakeStyleProvider(),
          prompts: _FakeSystemPromptProvider(),
        ),
      );
      await _openPicker(tester);

      expect(find.byKey(const ValueKey('capability_filter')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('capability_filter_vision')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('model_row_gemma3-vision')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('model_row_qwen3')), findsNothing);
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

  group('StyleProvider last-used persistence', () {
    // These use the real StyleProvider (not the picker-facing
    // _FakeStyleProvider) with a fake StyleService, so the actual
    // _seedPendingFromDefault logic runs.
    test(
      'seeds pendings from the last-used style when there is no default',
      () async {
        final style = _style(
          's1',
          'Deep work',
          thinkingLevel: ThinkingLevel.high,
        );
        final first = StyleProvider(styleService: _FakeStyleService([style]));
        await _waitForLoad(first);
        await first.recordLastUsed('s1');

        // Simulate the next app start: a fresh provider loads styles again
        // and should seed from the persisted last-used id.
        final restarted = StyleProvider(
          styleService: _FakeStyleService([style]),
        );
        await _waitForLoad(restarted);

        expect(restarted.pendingThinkingLevel, ThinkingLevel.high);
      },
    );

    test('an explicit default style wins over last-used', () async {
      final defaultStyle = _style(
        'default',
        'Default',
        thinkingLevel: ThinkingLevel.low,
        isDefault: true,
      );
      final lastUsed = _style(
        'last',
        'Last used',
        thinkingLevel: ThinkingLevel.high,
      );
      final seed = _FakeStyleService([defaultStyle, lastUsed]);
      final first = StyleProvider(styleService: seed);
      await _waitForLoad(first);
      await first.recordLastUsed('last');

      final restarted = StyleProvider(
        styleService: _FakeStyleService([defaultStyle, lastUsed]),
      );
      await _waitForLoad(restarted);

      // Default (low), not last-used (high), wins.
      expect(restarted.pendingThinkingLevel, ThinkingLevel.low);
    });

    test(
      'does not stomp pendings the user already composed in the picker',
      () async {
        final style = _style(
          's1',
          'Deep work',
          thinkingLevel: ThinkingLevel.high,
        );
        final provider = StyleProvider(
          styleService: _FakeStyleService([style]),
        );
        await _waitForLoad(provider);
        await provider.recordLastUsed('s1');

        // The user composes something in the picker before any further
        // refresh happens (e.g. after saving a new style).
        provider.setPendingThinkingLevel(ThinkingLevel.medium);
        await provider.refresh();
        await _waitForLoad(provider);

        expect(provider.pendingThinkingLevel, ThinkingLevel.medium);
      },
    );
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
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
  }) async =>
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
