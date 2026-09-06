import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/core/auth_state.dart';

void main() {
  test('a successful login advances the user-scoped provider epoch', () {
    final auth = AuthState();
    var notifications = 0;
    auth.addListener(() => notifications++);

    auth.markLoggedIn();

    expect(auth.loggedIn, isTrue);
    expect(auth.ready, isTrue);
    expect(auth.epoch, 1);
    expect(notifications, 1);
  });
}
