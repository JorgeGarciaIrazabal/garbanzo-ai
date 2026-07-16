import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';
import 'package:garbanzo_ai/features/friends/services/friends_service.dart';
import 'package:mocktail/mocktail.dart';

class MockFriendsService extends Mock implements FriendsService {}

const _friend = Friend(email: 'ana@example.com', friendshipId: 'f1');
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

  setUp(() {
    service = MockFriendsService();
    when(() => service.list()).thenAnswer((_) async => const FriendsList());
  });

  FriendsProvider provider() => FriendsProvider(service: service);

  group('refresh', () {
    test('populates friends and requests', () async {
      when(() => service.list()).thenAnswer(
        (_) async => const FriendsList(
          friends: [_friend],
          incomingRequests: [_incoming],
          outgoingRequests: [_outgoing],
        ),
      );

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.friends.single.email, 'ana@example.com');
      expect(p.incomingRequests.single.requesterEmail, 'bob@example.com');
      expect(p.outgoingRequests.single.addresseeEmail, 'carol@example.com');
      expect(p.error, isNull);
      p.dispose();
    });

    test('surfaces a load failure', () async {
      when(() => service.list()).thenThrow(Exception('API Error (500): boom'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.friends, isEmpty);
      expect(p.error, isNotNull);
      p.dispose();
    });
  });

  group('sendRequest', () {
    test('returns the status and reloads the list', () async {
      when(() => service.sendRequest('bob@example.com'))
          .thenAnswer((_) async => 'pending');

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      when(() => service.list()).thenAnswer(
        (_) async => const FriendsList(outgoingRequests: [_outgoing]),
      );

      final status = await p.sendRequest('bob@example.com');

      expect(status, 'pending');
      expect(p.outgoingRequests, hasLength(1));
      p.dispose();
    });

    test('surfaces the backend detail on failure', () async {
      when(() => service.sendRequest('nobody@example.com'))
          .thenThrow(Exception('API Error (400): No user with that email'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      final status = await p.sendRequest('nobody@example.com');

      expect(status, isNull);
      expect(p.error, contains('No user with that email'));
      p.dispose();
    });
  });

  group('accept / decline / remove', () {
    test('accept calls the service and reloads', () async {
      when(() => service.accept('r1')).thenAnswer((_) async {});

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      when(() => service.list()).thenAnswer(
        (_) async => const FriendsList(friends: [_friend]),
      );

      expect(await p.accept(_incoming), isTrue);
      expect(p.friends, hasLength(1));
      verify(() => service.accept('r1')).called(1);
      p.dispose();
    });

    test('decline failure returns false and sets error', () async {
      when(() => service.decline('r1'))
          .thenThrow(Exception('API Error (404): Friend request not found'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(await p.decline(_incoming), isFalse);
      expect(p.error, isNotNull);
      p.dispose();
    });

    test('remove calls the service and reloads', () async {
      when(() => service.remove('ana@example.com')).thenAnswer((_) async {});

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(await p.remove('ana@example.com'), isTrue);
      verify(() => service.remove('ana@example.com')).called(1);
      p.dispose();
    });
  });

  group('block / unblock', () {
    test('block calls the service and the list gains the blocked entry',
        () async {
      when(() => service.block('ana@example.com')).thenAnswer((_) async {});

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      when(() => service.list()).thenAnswer(
        (_) async => const FriendsList(blocked: [_friend]),
      );

      expect(await p.block('ana@example.com'), isTrue);
      expect(p.blocked.single.email, 'ana@example.com');
      p.dispose();
    });

    test('unblock failure returns false and sets error', () async {
      when(() => service.unblock('ana@example.com'))
          .thenThrow(Exception('API Error (404): Block not found'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(await p.unblock('ana@example.com'), isFalse);
      expect(p.error, isNotNull);
      p.dispose();
    });
  });

  group('models', () {
    test('FriendsList.fromJson parses the backend shape', () {
      final list = FriendsList.fromJson({
        'friends': [
          {
            'email': 'ana@example.com',
            'full_name': 'Ana',
            'friendship_id': 'f1',
            'since': '2026-07-01T12:00:00Z',
          },
        ],
        'incoming_requests': [
          {
            'id': 'r1',
            'requester_email': 'bob@example.com',
            'addressee_email': 'me@example.com',
            'created_at': '2026-07-02T12:00:00Z',
          },
        ],
        'outgoing_requests': [],
      });

      expect(list.friends.single.displayName, 'Ana');
      expect(list.friends.single.since, isNotNull);
      expect(list.incomingRequests.single.id, 'r1');
      expect(list.outgoingRequests, isEmpty);
    });

    test('displayName falls back to email', () {
      expect(_friend.displayName, 'ana@example.com');
    });
  });
}
