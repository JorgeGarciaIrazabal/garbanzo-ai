import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/models/share_models.dart';
import 'package:garbanzo_ai/features/friends/providers/friends_provider.dart';
import 'package:garbanzo_ai/features/friends/services/friends_service.dart';
import 'package:garbanzo_ai/features/friends/services/shares_service.dart';
import 'package:mocktail/mocktail.dart';

class MockFriendsService extends Mock implements FriendsService {}

class MockSharesService extends Mock implements SharesService {}

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
  late MockSharesService shares;

  setUp(() {
    service = MockFriendsService();
    shares = MockSharesService();
    when(() => service.list()).thenAnswer((_) async => const FriendsList());
    when(() => shares.incoming()).thenAnswer((_) async => const []);
  });

  FriendsProvider provider() =>
      FriendsProvider(service: service, sharesService: shares);

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

  group('shares', () {
    const share = SharedItem(
      id: 's1',
      senderEmail: 'ana@example.com',
      kind: 'prompt',
      payload: {'name': 'Concise', 'content': 'Be brief.'},
    );

    test('refresh loads incoming shares', () async {
      when(() => shares.incoming()).thenAnswer((_) async => const [share]);

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.incomingShares.single.name, 'Concise');
      p.dispose();
    });

    test('acceptShare calls the service and re-fetches', () async {
      when(() => shares.incoming()).thenAnswer((_) async => const [share]);
      when(() => shares.accept('s1')).thenAnswer((_) async => 'new-id');

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      when(() => shares.incoming()).thenAnswer((_) async => const []);

      expect(await p.acceptShare(share), isTrue);
      expect(p.incomingShares, isEmpty);
      p.dispose();
    });

    test('shareItem surfaces the backend detail on failure', () async {
      when(
        () => shares.share(
          kind: 'style',
          itemId: 'st1',
          recipientEmail: 'x@example.com',
        ),
      ).thenThrow(Exception('API Error (400): You can only share with your friends.'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      final ok = await p.shareItem(
        kind: 'style',
        itemId: 'st1',
        recipientEmail: 'x@example.com',
      );

      expect(ok, isFalse);
      expect(p.error, contains('only share with your friends'));
      p.dispose();
    });

    test('SharedItem.fromJson parses the backend shape', () {
      final item = SharedItem.fromJson({
        'id': 's1',
        'sender_email': 'ana@example.com',
        'kind': 'style',
        'payload': {'name': 'Deep Work', 'model_id': 'llama3'},
        'created_at': '2026-07-10T10:00:00Z',
      });
      expect(item.name, 'Deep Work');
      expect(item.kind, 'style');
      expect(item.createdAt, isNotNull);
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
