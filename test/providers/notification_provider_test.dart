import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/notifications/models/app_notification.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';
import 'package:garbanzo_ai/features/notifications/services/notification_api_service.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationApiService extends Mock
    implements NotificationApiService {}

AppNotification _notification(String id, {bool isRead = false}) {
  return AppNotification(
    id: id,
    channel: 'chat_responses',
    title: 'Title $id',
    body: 'Body $id',
    isRead: isRead,
    createdAt: DateTime.utc(2026),
  );
}

const _prefs = NotificationPreferences(
  chatResponsesEnabled: true,
  remindersEnabled: true,
  systemAlertsEnabled: false,
);

void main() {
  late MockNotificationApiService service;

  setUp(() {
    service = MockNotificationApiService();
    // Default: empty inbox. Individual tests override.
    when(() => service.list()).thenAnswer(
      (_) async => const NotificationListResult(items: [], unreadCount: 0),
    );
  });

  NotificationProvider provider() => NotificationProvider(service: service);

  group('refresh', () {
    test('populates items and unread count', () async {
      when(() => service.list()).thenAnswer(
        (_) async => NotificationListResult(
          items: [_notification('n1'), _notification('n2', isRead: true)],
          unreadCount: 1,
        ),
      );

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.items.map((n) => n.id), ['n1', 'n2']);
      expect(p.unreadCount, 1);
      expect(p.error, isNull);
      p.dispose();
    });

    test('surfaces a load failure', () async {
      when(() => service.list()).thenThrow(Exception('API Error (500): boom'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.items, isEmpty);
      expect(p.error, isNotNull);
      p.dispose();
    });
  });

  group('markRead', () {
    test('optimistically flags the item and decrements the badge', () async {
      when(() => service.list()).thenAnswer(
        (_) async => NotificationListResult(
          items: [_notification('n1'), _notification('n2')],
          unreadCount: 2,
        ),
      );
      when(() => service.markRead('n1')).thenAnswer((_) async {});

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.markRead('n1');

      expect(p.items.first.isRead, isTrue);
      expect(p.items.last.isRead, isFalse);
      expect(p.unreadCount, 1);
      verify(() => service.markRead('n1')).called(1);
      p.dispose();
    });

    test('is a no-op for already-read or unknown ids', () async {
      when(() => service.list()).thenAnswer(
        (_) async => NotificationListResult(
          items: [_notification('n1', isRead: true)],
          unreadCount: 0,
        ),
      );

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.markRead('n1');
      await p.markRead('missing');

      verifyNever(() => service.markRead(any()));
      expect(p.unreadCount, 0);
      p.dispose();
    });

    test('keeps the optimistic state even if the API call fails', () async {
      when(() => service.list()).thenAnswer(
        (_) async => NotificationListResult(
          items: [_notification('n1')],
          unreadCount: 1,
        ),
      );
      when(() => service.markRead('n1'))
          .thenThrow(Exception('API Error (500): nope'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.markRead('n1');

      expect(p.items.single.isRead, isTrue);
      expect(p.unreadCount, 0);
      p.dispose();
    });
  });

  group('markAllRead', () {
    test('flags everything and zeroes the badge', () async {
      when(() => service.list()).thenAnswer(
        (_) async => NotificationListResult(
          items: [_notification('n1'), _notification('n2')],
          unreadCount: 2,
        ),
      );
      when(() => service.markAllRead()).thenAnswer((_) async {});

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.markAllRead();

      expect(p.items.every((n) => n.isRead), isTrue);
      expect(p.unreadCount, 0);
      p.dispose();
    });

    test('skips the API call when nothing is unread', () async {
      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.markAllRead();

      verifyNever(() => service.markAllRead());
      p.dispose();
    });
  });

  group('remove', () {
    test('drops the item and refreshes the badge from the server', () async {
      when(() => service.list()).thenAnswer(
        (_) async => NotificationListResult(
          items: [_notification('n1'), _notification('n2')],
          unreadCount: 2,
        ),
      );
      when(() => service.delete('n1')).thenAnswer((_) async {});
      when(() => service.unreadCount()).thenAnswer((_) async => 1);

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.remove('n1');

      expect(p.items.map((n) => n.id), ['n2']);
      expect(p.unreadCount, 1);
      p.dispose();
    });
  });

  group('preferences', () {
    test('loadPreferences stores the result', () async {
      when(() => service.getPreferences()).thenAnswer((_) async => _prefs);

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.loadPreferences();

      expect(p.preferences?.systemAlertsEnabled, isFalse);
      expect(p.loadingPreferences, isFalse);
      p.dispose();
    });

    test('updatePreferences applies optimistically then keeps server truth',
        () async {
      when(() => service.getPreferences()).thenAnswer((_) async => _prefs);
      when(
        () => service.updatePreferences(
          chatResponsesEnabled: any(named: 'chatResponsesEnabled'),
          remindersEnabled: any(named: 'remindersEnabled'),
          systemAlertsEnabled: any(named: 'systemAlertsEnabled'),
        ),
      ).thenAnswer(
        (_) async => _prefs.copyWith(systemAlertsEnabled: true),
      );

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.loadPreferences();
      await p.updatePreferences(systemAlertsEnabled: true);

      expect(p.preferences?.systemAlertsEnabled, isTrue);
      p.dispose();
    });

    test('a failed update reloads preferences from the server', () async {
      when(() => service.getPreferences()).thenAnswer((_) async => _prefs);
      when(
        () => service.updatePreferences(
          chatResponsesEnabled: any(named: 'chatResponsesEnabled'),
          remindersEnabled: any(named: 'remindersEnabled'),
          systemAlertsEnabled: any(named: 'systemAlertsEnabled'),
        ),
      ).thenThrow(Exception('API Error (500): nope'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.loadPreferences();
      await p.updatePreferences(systemAlertsEnabled: true);

      // Rolled back to the server state.
      expect(p.preferences?.systemAlertsEnabled, isFalse);
      p.dispose();
    });
  });
}
