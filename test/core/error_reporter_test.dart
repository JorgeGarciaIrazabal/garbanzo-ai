import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/core/error_reporter.dart';

void main() {
  test('debounces a fingerprint and reads the latest chat context', () async {
    final payloads = <Map<String, dynamic>>[];
    final reporter = ErrorReporter(
      submit: (payload) async => payloads.add(payload),
      appVersion: () async => '1.2.3',
    )..setContext(
      conversationId: 'conversation-1',
      messageId: 'message-1',
      context: {'surface': 'chat'},
    );

    final stack = StackTrace.fromString('frame one\nframe two');
    await reporter.report(StateError('boom'), stack);
    await reporter.report(StateError('boom'), stack);

    expect(payloads, hasLength(1));
    expect(payloads.single['conversation_id'], 'conversation-1');
    final metadata = payloads.single['metadata'] as Map<String, dynamic>;
    expect(metadata['message_id'], 'message-1');
    expect(metadata['app_version'], '1.2.3');
    expect(metadata['context'], {'conversation_id': 'conversation-1', 'message_id': 'message-1', 'surface': 'chat'});
  });

  test('a failed report submission cannot recursively file another report', () async {
    var calls = 0;
    late ErrorReporter reporter;
    reporter = ErrorReporter(
      appVersion: () async => '1.2.3',
      submit: (_) async {
        calls++;
        await reporter.report(StateError('report transport failed'), StackTrace.current);
      },
    );

    await reporter.report(StateError('original failure'), StackTrace.current);

    expect(calls, 1);
  });
}
