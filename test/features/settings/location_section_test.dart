import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/settings/widgets/location_section.dart';

Widget _wrap(UserInfo? user) => MaterialApp(
  home: Scaffold(
    body: LocationSection(user: user, onUserChanged: () {}),
  ),
);

void main() {
  testWidgets('sharing is off by default (no stored location)', (tester) async {
    await tester.pumpWidget(_wrap(const UserInfo(email: 'a@b.c')));
    expect(tester.takeException(), isNull);

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('location_sharing_switch')),
    );
    expect(toggle.value, isFalse);
    expect(find.byKey(const ValueKey('location_edit_tile')), findsNothing);
  });

  testWidgets('a stored location shows as sharing-on with the city visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const UserInfo(email: 'a@b.c', location: 'Madrid, Spain')),
    );

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('location_sharing_switch')),
    );
    expect(toggle.value, isTrue);
    expect(find.byKey(const ValueKey('location_edit_tile')), findsOneWidget);
    expect(find.text('Madrid, Spain'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('location_refresh_button')),
      findsOneWidget,
    );
  });

  testWidgets('null user renders safely as sharing-off', (tester) async {
    await tester.pumpWidget(_wrap(null));
    expect(tester.takeException(), isNull);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('location_sharing_switch')),
    );
    expect(toggle.value, isFalse);
  });
}
