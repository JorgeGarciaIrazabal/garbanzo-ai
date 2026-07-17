import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/notifications/models/app_notification.dart';
import 'package:garbanzo_ai/features/notifications/pages/notifications_page.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';
import 'package:garbanzo_ai/features/notifications/services/notification_api_service.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class MockNotificationApiService extends Mock
    implements NotificationApiService {}

void main() {
  late MockNotificationApiService service;

  setUp(() {
    service = MockNotificationApiService();
    when(() => service.markRead(any())).thenAnswer((_) async {});
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsPage(),
        ),
        GoRoute(
          path: '/chat/:conversationId',
          builder: (context, state) => Scaffold(
            body: Text('chat:${state.pathParameters['conversationId']}'),
          ),
        ),
        GoRoute(
          path: '/rooms/:roomId',
          builder: (context, state) =>
              Scaffold(body: Text('room:${state.pathParameters['roomId']}')),
        ),
      ],
    );

    return ChangeNotifierProvider(
      create: (_) => NotificationProvider(service: service),
      child: MaterialApp.router(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
routerConfig: router),
    );
  }

  testWidgets('tapping a notification with a conversation_id navigates to it '
      '(B-02)', (tester) async {
    when(() => service.list()).thenAnswer(
      (_) async => NotificationListResult(
        items: [
          AppNotification(
            id: 'n1',
            channel: 'chat_responses',
            title: 'Response ready',
            body: 'Here is your answer',
            isRead: false,
            createdAt: DateTime.utc(2026),
            data: const {'conversation_id': 'c1'},
          ),
        ],
        unreadCount: 1,
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Response ready'));
    await tester.pumpAndSettle();

    expect(find.text('chat:c1'), findsOneWidget);
    verify(() => service.markRead('n1')).called(1);
  });

  testWidgets('tapping a notification with no navigable data just marks read',
      (tester) async {
    when(() => service.list()).thenAnswer(
      (_) async => NotificationListResult(
        items: [
          AppNotification(
            id: 'n1',
            channel: 'system_alerts',
            title: 'Heads up',
            body: 'Nothing to open',
            isRead: false,
            createdAt: DateTime.utc(2026),
          ),
        ],
        unreadCount: 1,
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Heads up'));
    await tester.pumpAndSettle();

    expect(find.text('Heads up'), findsOneWidget); // still on the same page
    verify(() => service.markRead('n1')).called(1);
  });
}
