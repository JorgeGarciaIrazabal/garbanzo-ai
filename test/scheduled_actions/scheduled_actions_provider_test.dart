import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/scheduled_actions/models/scheduled_action.dart';
import 'package:garbanzo_ai/features/scheduled_actions/providers/scheduled_actions_provider.dart';
import 'package:garbanzo_ai/features/scheduled_actions/services/scheduled_actions_api_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ScheduledActionsApiService {}

ScheduledAction _action({
  String id = 'a1',
  bool isActive = true,
}) {
  return ScheduledAction(
    id: id,
    userId: 'u@example.com',
    prompt: 'Daily ping',
    cronExpr: '0 9 * * *',
    isActive: isActive,
    createdAt: DateTime.utc(2026, 4, 21),
    updatedAt: DateTime.utc(2026, 4, 21),
  );
}

void main() {
  late _MockApi api;
  late ScheduledActionsProvider provider;

  setUp(() {
    api = _MockApi();
    provider = ScheduledActionsProvider(service: api);
  });

  group('load', () {
    test('populates actions on success', () async {
      when(() => api.list()).thenAnswer(
        (_) async => [_action(id: '1'), _action(id: '2')],
      );

      expect(provider.actions, isEmpty);
      await provider.load();

      expect(provider.actions, hasLength(2));
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });

    test('stores error message on failure', () async {
      when(() => api.list()).thenThrow(Exception('network down'));

      await provider.load();

      expect(provider.actions, isEmpty);
      expect(provider.error, contains('Failed to load scheduled actions'));
      expect(provider.loading, isFalse);
    });
  });

  group('create', () {
    test('prepends the created action on success', () async {
      when(
        () => api.create(
          prompt: any(named: 'prompt'),
          title: any(named: 'title'),
          cronExpr: any(named: 'cronExpr'),
          runAt: any(named: 'runAt'),
          systemPrompt: any(named: 'systemPrompt'),
          model: any(named: 'model'),
        ),
      ).thenAnswer((_) async => _action(id: 'new'));

      final result = await provider.create(
        prompt: 'Daily ping',
        title: 'Morning',
        cronExpr: '0 9 * * *',
      );
      expect(result?.id, 'new');
      expect(provider.actions, hasLength(1));
      expect(provider.actions.first.id, 'new');
    });

    test('sets error and returns null on failure', () async {
      when(
        () => api.create(
          prompt: any(named: 'prompt'),
          title: any(named: 'title'),
          cronExpr: any(named: 'cronExpr'),
          runAt: any(named: 'runAt'),
          systemPrompt: any(named: 'systemPrompt'),
          model: any(named: 'model'),
        ),
      ).thenThrow(Exception('bad cron'));

      final result = await provider.create(
        prompt: 'x',
        cronExpr: '0 9 * * *',
      );
      expect(result, isNull);
      expect(provider.error, contains('Failed to create scheduled action'));
      expect(provider.actions, isEmpty);
    });
  });

  group('setActive', () {
    test('replaces the action in the list', () async {
      when(() => api.list()).thenAnswer(
        (_) async => [_action(id: '1', isActive: true)],
      );
      when(
        () => api.update(
          any(),
          isActive: any(named: 'isActive'),
          title: any(named: 'title'),
          prompt: any(named: 'prompt'),
          cronExpr: any(named: 'cronExpr'),
          runAt: any(named: 'runAt'),
          systemPrompt: any(named: 'systemPrompt'),
          model: any(named: 'model'),
        ),
      ).thenAnswer((_) async => _action(id: '1', isActive: false));

      await provider.load();
      await provider.setActive('1', false);

      expect(provider.actions.single.isActive, isFalse);
    });

    test('sets error and preserves list on failure', () async {
      when(() => api.list()).thenAnswer(
        (_) async => [_action(id: '1', isActive: true)],
      );
      when(
        () => api.update(
          any(),
          isActive: any(named: 'isActive'),
          title: any(named: 'title'),
          prompt: any(named: 'prompt'),
          cronExpr: any(named: 'cronExpr'),
          runAt: any(named: 'runAt'),
          systemPrompt: any(named: 'systemPrompt'),
          model: any(named: 'model'),
        ),
      ).thenThrow(Exception('server down'));

      await provider.load();
      await provider.setActive('1', false);

      expect(provider.error, contains('Failed to update scheduled action'));
      expect(provider.actions.single.isActive, isTrue);
    });
  });

  group('delete', () {
    test('removes the action from the list on success', () async {
      when(() => api.list()).thenAnswer(
        (_) async => [_action(id: '1'), _action(id: '2')],
      );
      when(() => api.delete('1')).thenAnswer((_) async => Future.value());

      await provider.load();
      await provider.delete('1');

      expect(provider.actions, hasLength(1));
      expect(provider.actions.single.id, '2');
    });

    test('keeps the list and sets error on failure', () async {
      when(() => api.list()).thenAnswer((_) async => [_action(id: '1')]);
      when(() => api.delete('1')).thenThrow(Exception('nope'));

      await provider.load();
      await provider.delete('1');

      expect(provider.actions, hasLength(1));
      expect(provider.error, contains('Failed to delete scheduled action'));
    });
  });

  test('clearError wipes the error message', () async {
    when(() => api.list()).thenThrow(Exception('x'));
    await provider.load();
    expect(provider.error, isNotNull);
    provider.clearError();
    expect(provider.error, isNull);
  });
}
