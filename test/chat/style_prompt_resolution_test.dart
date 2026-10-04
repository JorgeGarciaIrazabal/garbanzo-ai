import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/services/style_service.dart';
import 'package:garbanzo_ai/features/chat/services/system_prompt_service.dart';

class _Styles extends StyleService {
  _Styles(this.rows) : super.forTesting();
  final List<Style> rows;

  @override
  Future<List<Style>> listStyles() async => rows;
}

class _Prompts extends SystemPromptService {
  _Prompts(this.rows) : super.forTesting();
  final List<SystemPromptTemplate> rows;
  final List<String?> locales = [];
  Future<List<SystemPromptTemplate>> Function(String? locale)? load;

  @override
  Future<List<SystemPromptTemplate>> listTemplates({String? locale}) async {
    locales.add(locale);
    if (load != null) return load!(locale);
    return rows.where((t) => locale == null || t.locale == locale).toList();
  }

  @override
  Future<String?> getUserDefault() async => null;
}

Style _style({String? reference = 'spanish', bool isDefault = true}) => Style(
  id: 'saved-style',
  name: 'Saved persona',
  modelId: 'model',
  thinkingLevel: ThinkingLevel.high,
  systemPromptTemplateId: reference,
  isDefault: isDefault,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

SystemPromptTemplate _prompt(String id, String content, {String? locale}) =>
    SystemPromptTemplate(
      id: id,
      name: id,
      content: content,
      locale: locale,
      isBuiltin: true,
      createdAt: DateTime(2026),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shared resolver distinguishes absent, empty, missing and transport failure', () async {
    final service = _Prompts([_prompt('empty', '')]);
    expect(await service.resolveTemplate(null), isNull);
    expect(service.locales, isEmpty);
    expect((await service.resolveTemplate('empty'))?.content, '');
    await expectLater(service.resolveTemplate('missing'), throwsStateError);
    final failure = DioException(
      requestOptions: RequestOptions(path: '/system-prompts/templates'),
      type: DioExceptionType.connectionError,
    );
    service.load = (_) => Future.error(failure);
    await expectLater(service.resolveTemplate('required'), throwsA(same(failure)));
  });

  test('explicit provider resolves a reference outside its visible locale', () async {
    final service = _Prompts([
      _prompt('english', 'English instructions', locale: 'en'),
      _prompt('spanish', 'Instrucciones', locale: 'es'),
    ]);
    final provider = SystemPromptProvider(systemPromptService: service);
    await provider.refresh(locale: 'en');
    expect(provider.templates.map((t) => t.id), ['english']);

    final resolved = await provider.resolveTemplate('spanish');

    expect(resolved?.content, 'Instrucciones');
    expect(service.locales.last, isNull);
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('explicit provider surfaces missing and transport lookup, then retries', () async {
    final service = _Prompts([]);
    final provider = SystemPromptProvider(systemPromptService: service);
    await provider.refresh(locale: 'en');
    expect(await provider.resolveTemplate('spanish'), isNull);
    expect(provider.error, isNotNull);
    service.load = (_) => Future.error(DioException(
      requestOptions: RequestOptions(path: '/system-prompts/templates'),
      type: DioExceptionType.connectionError,
    ));
    expect(await provider.resolveTemplate('spanish'), isNull);
    expect(provider.error, contains("Can't reach the server"));
    service.load = (_) async => [_prompt('spanish', 'Recovered')];
    expect((await provider.resolveTemplate('spanish'))?.content, 'Recovered');
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('startup and new topic resolve across locales and publish settings together', () async {
    final prompts = _Prompts([
      _prompt('spanish', 'Instrucciones', locale: 'es'),
    ]);
    final provider = StyleProvider(
      styleService: _Styles([_style()]),
      systemPromptService: prompts,
    );
    final snapshots = <(String?, ThinkingLevel?, String?)>[];
    provider.addListener(() => snapshots.add((
      provider.selectedStyleId,
      provider.pendingThinkingLevel,
      provider.pendingSystemPrompt,
    )));
    await provider.ensureLoaded();
    expect(provider.pendingSystemPrompt, 'Instrucciones');
    expect(provider.pendingThinkingLevel, ThinkingLevel.high);
    expect(provider.selectedStyleId, 'saved-style');
    expect(snapshots.every((s) => s == (null, null, null) ||
        s == ('saved-style', ThinkingLevel.high, 'Instrucciones')), isTrue);
    snapshots.clear();
    await provider.applyDefaultForNewTopic();
    expect(provider.pendingThinkingLevel, ThinkingLevel.medium);
    expect(provider.pendingSystemPrompt, 'Instrucciones');
    expect(snapshots.every((s) =>
        s == ('saved-style', ThinkingLevel.high, 'Instrucciones') ||
        s == ('saved-style', ThinkingLevel.medium, 'Instrucciones')), isTrue);
    expect(prompts.locales.every((l) => l == null), isTrue);
    expect(provider.pendingSeedBlocked, isFalse);
    provider.dispose();
  });

  for (final transportFailure in [false, true]) {
    test('startup ${transportFailure ? 'transport' : 'missing'} failure blocks new topic until retry', () async {
      final prompts = _Prompts([]);
      if (transportFailure) {
        prompts.load = (_) => Future.error(DioException(
          requestOptions: RequestOptions(path: '/system-prompts/templates'),
          type: DioExceptionType.connectionError,
        ));
      }
      final provider = StyleProvider(
        styleService: _Styles([_style()]),
        systemPromptService: prompts,
      );
      await provider.ensureLoaded();
      expect(provider.seedError, isNotNull);
      expect(provider.selectedStyleId, isNull);
      expect(provider.pendingThinkingLevel, isNull);
      expect(provider.pendingSystemPrompt, isNull);
      expect(provider.pendingSeedBlocked, isTrue);
      expect(await provider.applyDefaultForNewTopic(), isNull);
      expect(provider.selectedStyleId, isNull);
      expect(provider.pendingThinkingLevel, isNull);
      expect(provider.pendingSeedBlocked, isTrue);

      prompts.load = (_) async => [_prompt('spanish', 'Recovered')];
      expect((await provider.applyDefaultForNewTopic())?.id, 'saved-style');
      expect(provider.seedError, isNull);
      expect(provider.pendingThinkingLevel, ThinkingLevel.medium);
      expect(provider.pendingSystemPrompt, 'Recovered');
      expect(provider.pendingSeedBlocked, isFalse);
      provider.dispose();
    });
  }

  test('failed new-topic lookup keeps the previously composed settings intact', () async {
    final prompts = _Prompts([_prompt('spanish', 'Initial')]);
    final provider = StyleProvider(
      styleService: _Styles([_style()]),
      systemPromptService: prompts,
    );
    await provider.ensureLoaded();
    provider.setPendingThinkingLevel(ThinkingLevel.off);
    provider.setPendingSystemPrompt('My own prompt');
    prompts.load = (_) async => [];
    final revision = provider.pendingRevision;
    await provider.applyDefaultForNewTopic();
    expect(provider.pendingRevision, revision);
    expect(provider.pendingThinkingLevel, ThinkingLevel.off);
    expect(provider.pendingSystemPrompt, 'My own prompt');
    expect(provider.seedError, isNotNull);
    expect(provider.pendingSeedBlocked, isTrue);
    provider.setPendingThinkingLevel(ThinkingLevel.low);
    expect(provider.pendingSeedBlocked, isTrue, reason: 'Effort cannot discard required instructions');
    provider.setPendingSystemPrompt('Explicit replacement');
    expect(provider.pendingSeedBlocked, isFalse);
    expect(provider.seedError, isNull);
    provider.dispose();
  });

  test('absent reference and deliberately empty instructions need no fallback', () async {
    for (final reference in <String?>[null, 'empty']) {
      final prompts = _Prompts([_prompt('empty', '')]);
      final provider = StyleProvider(
        styleService: _Styles([_style(reference: reference)]),
        systemPromptService: prompts,
      );
      await provider.ensureLoaded();
      await provider.applyDefaultForNewTopic();
      expect(provider.pendingSystemPrompt, isNull);
      expect(provider.pendingThinkingLevel, ThinkingLevel.medium);
      expect(provider.selectedStyleId, 'saved-style');
      expect(provider.seedError, isNull);
      expect(provider.pendingSeedBlocked, isFalse);
      if (reference == null) expect(prompts.locales, isEmpty);
      provider.dispose();
    }
  });

  test('a slower seed cannot overwrite a newer new-topic result', () async {
    final prompts = _Prompts([_prompt('spanish', 'Initial')]);
    final provider = StyleProvider(
      styleService: _Styles([_style()]),
      systemPromptService: prompts,
    );
    await provider.ensureLoaded();
    final slow = Completer<List<SystemPromptTemplate>>();
    final started = Completer<void>();
    prompts.load = (_) {
      started.complete();
      return slow.future;
    };
    final older = provider.applyDefaultForNewTopic();
    await started.future;
    prompts.load = (_) async => [_prompt('spanish', 'Newer')];
    await provider.applyDefaultForNewTopic();
    slow.complete([_prompt('spanish', 'Older')]);
    expect(await older, isNull);
    expect(provider.pendingSystemPrompt, 'Newer');
    expect(provider.pendingThinkingLevel, ThinkingLevel.medium);
    expect(provider.seedError, isNull);
    provider.dispose();
  });

  test('late startup lookup cannot replace explicit composer customization', () async {
    final slow = Completer<List<SystemPromptTemplate>>();
    final started = Completer<void>();
    final prompts = _Prompts([])..load = (_) {
      started.complete();
      return slow.future;
    };
    final provider = StyleProvider(
      styleService: _Styles([_style()]),
      systemPromptService: prompts,
    );
    await started.future;
    provider.clearSelectedStyle();
    provider.setPendingThinkingLevel(ThinkingLevel.low);
    provider.setPendingSystemPrompt('Custom instructions');
    slow.complete([_prompt('spanish', 'Late default')]);
    await provider.ensureLoaded();
    expect(provider.selectedStyleId, isNull);
    expect(provider.pendingThinkingLevel, ThinkingLevel.low);
    expect(provider.pendingSystemPrompt, 'Custom instructions');
    expect(provider.seedError, isNull);
    expect(provider.pendingSeedBlocked, isFalse);
    provider.dispose();
  });

  test('closing the landing while lookup runs discards its pending result', () async {
    final prompts = _Prompts([_prompt('spanish', 'Initial')]);
    final provider = StyleProvider(
      styleService: _Styles([_style()]),
      systemPromptService: prompts,
    );
    await provider.ensureLoaded();
    final slow = Completer<List<SystemPromptTemplate>>();
    final started = Completer<void>();
    prompts.load = (_) {
      started.complete();
      return slow.future;
    };
    var current = true;
    final result = provider.applyDefaultForNewTopic(isCurrent: () => current);
    await started.future;
    current = false;
    slow.complete([_prompt('spanish', 'Stale')]);
    expect(await result, isNull);
    expect(provider.pendingSystemPrompt, 'Initial');
    expect(provider.pendingThinkingLevel, ThinkingLevel.high);
    provider.dispose();
  });
}
