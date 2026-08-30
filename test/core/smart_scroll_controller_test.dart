import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/smart_scroll_controller.dart';

const viewportHeight = 300.0;

/// A minimal scrolling page: a 50px header, then the keyed streaming bubble.
Widget page(SmartScrollController scroll, double bubbleHeight) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 200,
          height: viewportHeight,
          child: ListView(
            controller: scroll.controller,
            children: [
              const SizedBox(height: 50),
              KeyedSubtree(
                key: scroll.streamAnchorKey,
                child: SizedBox(
                  height: bubbleHeight,
                  child: const ColoredBox(color: Color(0xFF00FF00)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'the answer top is pinned at the viewport top for the whole stream — '
    'the view never moves again once pinned',
    (tester) async {
      final scroll = SmartScrollController();
      addTearDown(scroll.dispose);

      // Stream starts; user is at the bottom; the pin places the answer's
      // top (offset 50 = header height, clamped: content 150 < viewport).
      await tester.pumpWidget(page(scroll, 100));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, 0.0); // bubble top already visible

      // The answer grows far beyond the viewport: the pin keeps its top at
      // the viewport top and never moves again.
      await tester.pumpWidget(page(scroll, 900));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, 50.0);

      await tester.pumpWidget(page(scroll, 2400));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, 50.0);
    },
  );

  testWidgets(
    'a passive reader with the answer top already in view is never yanked '
    'and a user scroll-up is left alone',
    (tester) async {
      final scroll = SmartScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(page(scroll, 100));
      scroll.handleStreamingTick('m1');
      await tester.pump();

      // The answer grows and the pin moves the view once...
      await tester.pumpWidget(page(scroll, 1000));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, 50.0);

      // ...then the user swipes up mid-stream: the pin must not fight them.
      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pump();
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, lessThan(50.0));

      // And no later tick moves the view either.
      await tester.pumpWidget(page(scroll, 2000));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, lessThan(50.0));
    },
  );

  testWidgets(
    'jump-to-bottom pill rides the tail of a live stream until the user '
    'scrolls away',
    (tester) async {
      final scroll = SmartScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(page(scroll, 100));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      await tester.pumpWidget(page(scroll, 2000));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, 50.0); // pinned at the answer top

      // Explicit pill tap: pins to the tail (max = 50 + 2000 - 300).
      scroll.resumeFollow();
      await tester.pump();
      expect(scroll.controller.offset, 1750.0);

      // Tail-riding continues across growth (max = 50 + 2600 - 300).
      await tester.pumpWidget(page(scroll, 2600));
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, 2350.0);

      // A user scroll-up stops the ride.
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      scroll.handleStreamingTick('m1');
      await tester.pump();
      expect(scroll.controller.offset, lessThan(2350.0));
    },
  );

  testWidgets('a new stream re-arms when the user is near the bottom', (
    tester,
  ) async {
    final scroll = SmartScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(page(scroll, 100));
    scroll.handleStreamingTick('m1');
    await tester.pump();
    scroll.handleStreamingTick(null); // first stream ends
    await tester.pump();

    // Fresh answer starts while the user is at the bottom: the answer-top
    // pin arms again for the new stream.
    await tester.pumpWidget(page(scroll, 400));
    scroll.handleStreamingTick('m2');
    await tester.pump();
    expect(scroll.controller.offset, 50.0); // answer top at viewport top
  });
}
