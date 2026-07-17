import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/main.dart';

/// Regression test for the startup crash fixed by using `onGenerateTitle`
/// instead of resolving `AppLocalizations.of(context)!` before
/// `MaterialApp.router` is built.
///
/// Before the fix, the `Consumer<SettingsProvider>` builder in
/// `_GarbanzoAppState.build` called `AppLocalizations.of(context)!`.  That
/// `context` is above `MaterialApp`, so the `LocalizationsDelegate` has not
/// been installed yet and `AppLocalizations.of` returns null.  The null-check
/// operator `!` threw a `_TypeError` that crashed the app on every cold start.
///
/// The fix moves the lookup into `onGenerateTitle`, which Flutter calls with
/// a context that already has localizations available (inside MaterialApp's
/// Localizations subtree).
void main() {
  group('GarbanzoApp boot', () {
    testWidgets('builds without a null-check crash', (tester) async {
      await tester.pumpWidget(const GarbanzoApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The original bug threw a _TypeError during the first build.  If we
      // reach this assertion with no pending exception, the regression is
      // fixed.
      expect(tester.takeException(), isNull);

      // MaterialApp should be present and use onGenerateTitle (the fix)
      // rather than a static `title:` that required localizations above it.
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.onGenerateTitle, isNotNull);
    });
  });
}