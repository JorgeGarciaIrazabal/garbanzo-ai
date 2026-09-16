import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/features/chat/models/agent_progress.dart';
import 'package:garbanzo_ai/features/chat/widgets/progress/agent_progress_card.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Regression tests for how the progress object's headline reads.
///
/// The bug these lock down: the collapsed headline announced a bare status
/// ("Finished") once a run ended, which sat directly above the step list and
/// read as if it were itself a final step — while also replacing the last
/// action, which is the one thing the collapsed card exists to show.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  AgentStep step({
    String id = 'c1',
    String label = 'parser.dart',
    AgentProgressPhase phase = AgentProgressPhase.editing,
    bool started = true,
    bool done = true,
    bool failed = false,
  }) => AgentStep(
    id: id,
    toolName: 'edit',
    phase: phase,
    label: label,
    started: started,
    done: done,
    failed: failed,
  );

  testWidgets('a finished run names its last action, not "Finished"', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AgentProgressCard(
          progress: AgentProgress(
            steps: [step()],
            live: false,
          ),
        ),
      ),
    );
    // The step label is present...
    expect(find.textContaining('parser.dart'), findsOneWidget);
    // ...and the headline is not a bare status word standing in for a step.
    expect(find.text('Finished'), findsNothing);
  });

  testWidgets('a failed run leads with the failure', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentProgressCard(
          progress: AgentProgress(
            steps: [step(done: false, failed: true)],
            live: false,
          ),
        ),
      ),
    );
    expect(find.text('Failed'), findsWidgets);
  });

  testWidgets('a stopped run leads with the cancellation', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentProgressCard(
          progress: AgentProgress(
            steps: [step(done: false)],
            live: false,
          ),
        ),
      ),
    );
    // No stream-level "done" and a step still running is not a success: the
    // glyph must not claim completion.
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('live run shows the current action and a stop affordance', (
    tester,
  ) async {
    var stopped = false;
    await tester.pumpWidget(
      wrap(
        AgentProgressCard(
          progress: AgentProgress(
            steps: [step(started: true, done: false)],
            live: true,
            secondsSinceSignal: 2,
          ),
          onStop: () => stopped = true,
        ),
      ),
    );
    expect(find.textContaining('parser.dart'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent_progress_stop')));
    expect(stopped, isTrue);
  });

  testWidgets('expanded view lists every step in order', (tester) async {
    await tester.pumpWidget(
      wrap(
        AgentProgressCard(
          progress: AgentProgress(
            steps: [
              step(id: 'a', label: 'first.md', phase: AgentProgressPhase.reading),
              step(id: 'b', label: 'second.md'),
              step(id: 'c', label: 'third.md'),
            ],
            live: false,
          ),
        ),
      ),
    );
    // Collapsed by default once finished, so expand it.
    await tester.tap(find.byKey(const ValueKey('agent_progress_header')));
    await tester.pumpAndSettle();
    expect(find.textContaining('first.md'), findsOneWidget);
    expect(find.textContaining('second.md'), findsOneWidget);
    expect(find.textContaining('third.md'), findsWidgets);
  });

  testWidgets('a quiet live run says so instead of looking hung', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AgentProgressCard(
          progress: AgentProgress(
            steps: [step(done: false)],
            live: true,
            secondsSinceSignal: 120,
          ),
        ),
      ),
    );
    // The elapsed/quiet meta line must be present and mention the last signal.
    expect(find.textContaining('2m'), findsWidgets);
  });
}
