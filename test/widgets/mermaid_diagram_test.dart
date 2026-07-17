import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/mermaid_diagram.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void main() {
  group('MermaidDiagram', () {
    late ColorScheme colorScheme;

    setUp(() {
      colorScheme = const ColorScheme.light();
    });

    testWidgets('renders with valid mermaid code in test mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '''
graph TD
    A[Start] --> B[Process]
    B --> C[End]
''',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      // Verify the widget renders without errors
      expect(find.byType(MermaidDiagram), findsOneWidget);
      // In test mode, should show the placeholder
      expect(find.text('Mermaid Diagram'), findsOneWidget);
    });

    testWidgets('renders flowchart diagram in test mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '''
flowchart LR
    A[Hard] -->|text| B(Round)
    B --> C{Decision}
    C -->|One| D[Result one]
    C -->|Two| E[Result two]
''',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('renders sequence diagram in test mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '''
sequenceDiagram
    Alice->>John: Hello John, how are you?
    John-->>Alice: Great!
    Alice-)John: See you later!
''',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('renders class diagram in test mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '''
classDiagram
    Animal <|-- Duck
    Animal <|-- Fish
    Animal : +int age
    Animal : +String gender
    Animal: +isMammal()
    class Duck{
        +String beakColor
        +swim()
    }
''',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('renders state diagram in test mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '''
stateDiagram-v2
    [*] --> Still
    Still --> [*]
    Still --> Moving
    Moving --> Still
''',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('handles empty mermaid code in test mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('handles dark mode color scheme in test mode', (tester) async {
      final darkColorScheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: '''
graph TD
    A --> B
''',
              colorScheme: darkColorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('widget updates when mermaid code changes in test mode',
        (tester) async {
      const initialCode = 'graph TD\n    A --> B';
      const updatedCode = 'graph TD\n    A --> C';

      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: initialCode,
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);

      // Update with new code
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: updatedCode,
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('shows copy button in header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: 'graph TD\n    A --> B',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      // Verify copy button is present
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    });

    testWidgets('shows mermaid label in header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
            body: MermaidDiagram(
              mermaidCode: 'graph TD\n    A --> B',
              colorScheme: colorScheme,
              isTestMode: true,
            ),
          ),
        ),
      );

      // Verify mermaid label is shown
      expect(find.text('mermaid'), findsOneWidget);
    });
  });
}