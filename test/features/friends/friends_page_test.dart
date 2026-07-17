import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/pages/friends_page.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';
import 'package:garbanzo_ai/features/friends/services/friends_service.dart';
import 'package:garbanzo_ai/features/friends/services/shares_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class MockFriendsService extends Mock implements FriendsService {}

class MockSharesService extends Mock implements SharesService {}

const _friend = Friend(
  email: 'ana@example.com',
  friendshipId: 'f1',
  fullName: 'Ana Lopez',
);
const _incoming = FriendRequest(
  id: 'r1',
  requesterEmail: 'bob@example.com',
  addresseeEmail: 'me@example.com',
);
const _outgoing = FriendRequest(
  id: 'r2',
  requesterEmail: 'me@example.com',
  addresseeEmail: 'carol@example.com',
);

void main() {
  late MockFriendsService service;
  late MockSharesService shares;

  setUp(() {
    service = MockFriendsService();
    shares = MockSharesService();
    when(() => service.list()).thenAnswer((_) async => const FriendsList());
    when(() => shares.incoming()).thenAnswer((_) async => const []);
  });

  Widget app() => MaterialApp(
    
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: ChangeNotifierProvider(
      create: (_) => FriendsProvider(service: service, sharesService: shares),
      child: const FriendsPage(),
    ),
  );

  testWidgets('shows the empty state', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Your friends (0)'), findsOneWidget);
    expect(
      find.text('No friends yet. Send a request by email above.'),
      findsOneWidget,
    );
  });

  testWidgets('renders friends and both request sections', (tester) async {
    when(() => service.list()).thenAnswer(
      (_) async => const FriendsList(
        friends: [_friend],
        incomingRequests: [_incoming],
        outgoingRequests: [_outgoing],
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Incoming requests (1)'), findsOneWidget);
    expect(find.text('bob@example.com'), findsOneWidget);
    expect(find.text('Sent requests (1)'), findsOneWidget);
    expect(find.text('carol@example.com'), findsOneWidget);
    expect(find.text('Your friends (1)'), findsOneWidget);
    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget); // subtitle
  });

  testWidgets('sends a friend request from the email field', (tester) async {
    when(() => service.sendRequest('bob@example.com'))
        .thenAnswer((_) async => 'pending');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('friend_email_field')),
      'bob@example.com',
    );
    await tester.tap(find.byKey(const Key('send_friend_request_button')));
    await tester.pumpAndSettle();

    verify(() => service.sendRequest('bob@example.com')).called(1);
    expect(
      find.text('Friend request sent to bob@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('accepting an incoming request calls the service',
      (tester) async {
    when(() => service.list()).thenAnswer(
      (_) async => const FriendsList(incomingRequests: [_incoming]),
    );
    when(() => service.accept('r1')).thenAnswer((_) async {});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();

    verify(() => service.accept('r1')).called(1);
  });

  testWidgets('removing a friend asks for confirmation first', (tester) async {
    when(() => service.list()).thenAnswer(
      (_) async => const FriendsList(friends: [_friend]),
    );
    when(() => service.remove('ana@example.com')).thenAnswer((_) async {});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Friend actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Friend'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    verify(() => service.remove('ana@example.com')).called(1);
  });

  testWidgets('blocking a friend asks for confirmation first', (tester) async {
    when(() => service.list()).thenAnswer(
      (_) async => const FriendsList(friends: [_friend]),
    );
    when(() => service.block('ana@example.com')).thenAnswer((_) async {});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Friend actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Block User'), findsOneWidget);

    await tester.tap(find.text('Block').last); // dialog action button
    await tester.pumpAndSettle();

    verify(() => service.block('ana@example.com')).called(1);
  });

  testWidgets('blocked section lists users with an unblock action', (
    tester,
  ) async {
    when(() => service.list()).thenAnswer(
      (_) async => const FriendsList(
        blocked: [Friend(email: 'evil@example.com', friendshipId: 'f9')],
      ),
    );
    when(() => service.unblock('evil@example.com')).thenAnswer((_) async {});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Blocked (1)'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();

    verify(() => service.unblock('evil@example.com')).called(1);
  });

  testWidgets('shows a dismissible error banner on load failure',
      (tester) async {
    when(() => service.list())
        .thenThrow(Exception('API Error (500): boom'));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Server error — please try again.'), findsOneWidget);
  });
}
