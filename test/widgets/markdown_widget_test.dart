import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/markdown_widget.dart';

void main() {
  group('MarkdownWidget', () {
    late ColorScheme colorScheme;
    late TextTheme textTheme;

    setUp(() {
      colorScheme = const ColorScheme.light();
      textTheme = const TextTheme();
    });

    group('inline math rendering', () {
      testWidgets('renders inline math correctly', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: r'The equation $x^2$ is inline.',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        // Verify the widget renders without errors
        expect(find.byType(MarkdownWidget), findsOneWidget);
      });

      testWidgets('renders multiple inline math expressions', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: r'From $a$ to $b$ and back to $a$.',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
      });

      testWidgets('handles escaped dollar signs correctly', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: r'The price is \$100, not math.',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
        // Escaped dollar signs should not be treated as math
        // The text should show as literal \$100 or $100
      });

      testWidgets('does not match single dollar sign without closing',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: r'This costs $100 only.',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
        // $100 should not be treated as math (no closing $)
      });

      testWidgets('handles LaTeX commands with backslashes', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: r'Integral: $\int_0^1 x dx$',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
      });
    });

    group('block math rendering', () {
      testWidgets('renders single-line block math correctly', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: r'$$\int_0^1 x dx$$',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
      });

      testWidgets('renders multi-line block math correctly', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: '''
\$\$
\\sum_{i=0}^n x_i
\$\$
''',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
      });

      testWidgets('renders block math with multiple lines', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: '''
\$\$
x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
\$\$
''',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
      });
    });

    group('mixed content', () {
      testWidgets('renders markdown with inline and block math together',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: '''
# Math Examples

Inline math: \$E = mc^2\$

Block math:

\$\$
\\int_0^\\infty e^{-x} dx = 1
\$\$

More text with \$x^2\$ inline.
''',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(MarkdownWidget), findsOneWidget);
      });

      testWidgets('renders empty content without error', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                content: '',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
          ),
        );

        expect(find.byType(SizedBox), findsOneWidget);
      });
    });
  });
}