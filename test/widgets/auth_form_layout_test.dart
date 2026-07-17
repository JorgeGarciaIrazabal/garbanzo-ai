import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/widgets/auth_form_layout.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void main() {
  group('PasswordField', () {
    testWidgets('starts obscured and toggles visibility', (tester) async {
      final controller = TextEditingController(text: 'secret123');

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: Form(
              child: PasswordField(controller: controller),
            ),
          ),
        ),
      );

      TextField field = tester.widget(find.byType(TextField));
      expect(field.obscureText, isTrue);

      await tester.tap(find.byKey(const ValueKey('password_visibility_toggle')));
      await tester.pump();

      field = tester.widget(find.byType(TextField));
      expect(field.obscureText, isFalse);

      await tester.tap(find.byKey(const ValueKey('password_visibility_toggle')));
      await tester.pump();

      field = tester.widget(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets('calls onSubmit when submitted', (tester) async {
      final controller = TextEditingController(text: 'secret');
      var submitted = 0;

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: Form(
              child: PasswordField(
                controller: controller,
                onSubmit: () => submitted++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, 1);
    });

    testWidgets('validator rejects empty password', (tester) async {
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: Form(
              key: formKey,
              child: PasswordField(controller: controller),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('validator rejects passwords shorter than minLength', (tester) async {
      final controller = TextEditingController(text: '123');
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: Form(
              key: formKey,
              child: PasswordField(
                controller: controller,
                minLength: 6,
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('validator accepts password meeting minLength', (tester) async {
      final controller = TextEditingController(text: 'longenough');
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: Form(
              key: formKey,
              child: PasswordField(
                controller: controller,
                minLength: 6,
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isTrue);
    });
  });

  group('AuthSubmitButton', () {
    testWidgets('shows label when not loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: AuthSubmitButton(
              label: 'Sign in',
              isLoading: false,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows spinner when loading and button is disabled', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: AuthSubmitButton(
              label: 'Sign in',
              isLoading: true,
              onPressed: () => tapped++,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(tapped, 0, reason: 'button should be disabled while loading');
    });

    testWidgets('invokes onPressed when tapped', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: AuthSubmitButton(
              label: 'Go',
              isLoading: false,
              onPressed: () => tapped++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group('AuthErrorBanner', () {
    testWidgets('displays the message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(body: AuthErrorBanner(message: 'Something went wrong')),
        ),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('AuthFormLayout', () {
    testWidgets('renders icon, heading, and children', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: AuthFormLayout(
            icon: Icons.person,
            heading: 'Welcome',
            formKey: formKey,
            children: const [Text('child-widget')],
          ),
        ),
      );
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Garbanzo AI'), findsOneWidget);
      expect(find.text('child-widget'), findsOneWidget);
    });
  });
}
