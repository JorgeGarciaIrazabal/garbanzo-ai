import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/notifications/services/push_service.dart';

void main() {
  group('PushService.routeForData (B-02)', () {
    test('room_id routes to the room', () {
      expect(
        PushService.routeForData({'room_id': 'r1'}),
        '/rooms/r1',
      );
    });

    test('conversation_id routes to the chat page', () {
      expect(
        PushService.routeForData({'conversation_id': 'c1'}),
        '/chat/c1',
      );
    });

    test('room_id wins when both are present', () {
      expect(
        PushService.routeForData({'room_id': 'r1', 'conversation_id': 'c1'}),
        '/rooms/r1',
      );
    });

    test('unknown payload shapes route nowhere', () {
      expect(PushService.routeForData({}), isNull);
      expect(PushService.routeForData({'scheduled_action_id': 'a1'}), isNull);
    });
  });
}
