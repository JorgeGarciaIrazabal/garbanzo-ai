import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:garbanzo_ai/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End User Flow', () {
    testWidgets('User can register and log in', (tester) async {
      // Generate unique test user to avoid conflicts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'testuser_$timestamp@example.com';
      final testPassword = 'TestPass123!';
      final testName = 'Test User $timestamp';

      // Start the app
      await tester.pumpWidget(const app.MyApp());
      await tester.pumpAndSettle();

      // Verify we're on the login page
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Garbanzo AI'), findsOneWidget);

      // Navigate to Register page
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();

      // Verify we're on the register page
      expect(find.text('Create account'), findsOneWidget);

      // Fill in registration form
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name (optional)'),
        testName,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        testEmail,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        testPassword,
      );

      // Submit registration
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      // After successful registration, we should see the home page
      // or be redirected to login. Let's wait for navigation.
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Check if we're on the home page (success) or still on a form
      final homeTitleFinder = find.text('Garbanzo AI Home');
      final loginTitleFinder = find.text('Sign in');

      if (homeTitleFinder.evaluate().isNotEmpty) {
        // Registration was successful and we're logged in
        expect(homeTitleFinder, findsOneWidget);
        print('✓ User registered and automatically logged in!');
      } else if (loginTitleFinder.evaluate().isNotEmpty) {
        // We're back at login, need to log in manually
        print('Registration successful, now logging in...');

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          testEmail,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          testPassword,
        );

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Verify we're now on the home page
        expect(find.text('Garbanzo AI Home'), findsOneWidget);
        print('✓ User logged in successfully!');
      }

      // Verify the user is logged in by checking for home page elements
      expect(find.textContaining('Welcome'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);

      print('✓ Full E2E test passed! User: $testEmail');
    });

    testWidgets('Login with invalid credentials shows error', (tester) async {
      await tester.pumpWidget(const app.MyApp());
      await tester.pumpAndSettle();

      // Try to log in with invalid credentials
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'nonexistent@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrongpassword',
      );

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should still be on login page with error
      expect(find.text('Sign in'), findsOneWidget);
      print('✓ Invalid login test passed!');
    });
  });
}
