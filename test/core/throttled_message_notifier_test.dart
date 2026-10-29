import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/core/throttled_message_notifier.dart';

typedef _Msg = ({String id, String text});

void main() {
  group('ThrottledMessageNotifier', () {
    test(
      'publishes initial push immediately and coalesces within interval',
      () {
        fakeAsync((async) {
          final throttle = ThrottledMessageNotifier<_Msg>(
            idOf: (m) => m.id,
            interval: const Duration(milliseconds: 80),
          )..messageId = 'm1';

          final seen = <String?>[];
          throttle.notifier.addListener(
            () => seen.add(throttle.notifier.value?.text),
          );

          throttle.push((id: 'm1', text: 'H'));
          expect(seen, ['H']);

          throttle.push((id: 'm1', text: 'He'));
          throttle.push((id: 'm1', text: 'Hel'));
          throttle.push((id: 'm1', text: 'Hell'));
          // Still within 80ms window — listeners were not spammed.
          expect(seen, ['H']);

          async.elapse(const Duration(milliseconds: 80));
          expect(seen, ['H', 'Hell']);

          throttle.dispose();
        });
      },
    );

    test('force: true flushes immediately even inside throttle interval', () {
      fakeAsync((async) {
        final throttle = ThrottledMessageNotifier<_Msg>(idOf: (m) => m.id)
          ..messageId = 'm1';
        final seen = <String?>[];
        throttle.notifier.addListener(
          () => seen.add(throttle.notifier.value?.text),
        );

        throttle.push((id: 'm1', text: 'first'));
        throttle.push((id: 'm1', text: 'buffered'));
        throttle.push((id: 'm1', text: 'committed'), force: true);

        expect(seen, ['first', 'committed']);
        async.elapse(const Duration(milliseconds: 100));
        expect(seen, ['first', 'committed']);

        throttle.dispose();
      });
    });

    test('sync commits pending buffered item matching messageId', () {
      fakeAsync((async) {
        final throttle = ThrottledMessageNotifier<_Msg>(idOf: (m) => m.id)
          ..messageId = 'm1';
        final committed = <String>[];

        throttle.push((id: 'm1', text: 'chunk-1'));
        throttle.push((id: 'm1', text: 'chunk-12'));
        expect(throttle.notifier.value?.text, 'chunk-1');

        throttle.sync((m) => committed.add(m.text));
        expect(committed, ['chunk-12']);

        throttle.dispose();
      });
    });

    test('ignores stale buffered item when messageId changes before flush', () {
      fakeAsync((async) {
        final throttle = ThrottledMessageNotifier<_Msg>(idOf: (m) => m.id)
          ..messageId = 'm1';

        throttle.push((id: 'm1', text: 'first'));
        throttle.push((id: 'm1', text: 'stale-pending'));
        throttle.messageId = 'm2';

        async.elapse(const Duration(milliseconds: 100));
        expect(throttle.notifier.value?.text, 'first');

        throttle.dispose();
      });
    });

    test('clear cancels pending timer and resets state to null', () {
      fakeAsync((async) {
        final throttle = ThrottledMessageNotifier<_Msg>(idOf: (m) => m.id)
          ..messageId = 'm1';
        throttle.push((id: 'm1', text: 'a'));
        throttle.push((id: 'm1', text: 'ab'));
        throttle.clear();

        expect(throttle.notifier.value, isNull);
        expect(throttle.messageId, isNull);
        async.elapse(const Duration(milliseconds: 100));
        expect(throttle.notifier.value, isNull);

        throttle.dispose();
      });
    });
  });
}
