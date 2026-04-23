import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

Stream<String> _fromList(List<String> parts) async* {
  for (final p in parts) {
    yield p;
  }
}

void main() {
  group('parseSseChunks', () {
    test('parses a single complete event', () async {
      final stream = _fromList([
        'data: {"type":"chunk","content":"hi"}\n\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.type, 'chunk');
      expect(chunks.single.content, 'hi');
    });

    test('parses multiple events in one byte chunk', () async {
      final stream = _fromList([
        'data: {"type":"chunk","content":"a"}\n\n'
            'data: {"type":"chunk","content":"b"}\n\n'
            'data: {"type":"done","metadata":{}}\n\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks.map((c) => c.type).toList(),
          ['chunk', 'chunk', 'done']);
      expect(chunks[0].content, 'a');
      expect(chunks[1].content, 'b');
    });

    test(
        'reassembles a single event split across multiple byte chunks '
        '(regression: previously the event was silently dropped)',
        () async {
      // Split the JSON in the MIDDLE of the payload to mimic what TCP can do.
      final stream = _fromList([
        'data: {"type":"thi',
        'nking","content":"',
        'Hello"}\n\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.type, 'thinking');
      expect(chunks.single.content, 'Hello');
    });

    test('reassembles when the \\n\\n delimiter itself is split', () async {
      final stream = _fromList([
        'data: {"type":"chunk","content":"x"}\n',
        '\ndata: {"type":"chunk","content":"y"}\n\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks.map((c) => c.content).toList(), ['x', 'y']);
    });

    test('skips [DONE] sentinel and unparsable lines', () async {
      final stream = _fromList([
        'data: [DONE]\n\n',
        'event: ping\n\n',
        'data: not-json\n\n',
        'data: {"type":"chunk","content":"ok"}\n\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.content, 'ok');
    });

    test('flushes a trailing event without a final blank line', () async {
      final stream = _fromList([
        'data: {"type":"chunk","content":"trail"}\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.content, 'trail');
    });

    test('parses a tool_call event with nested arguments', () async {
      final stream = _fromList([
        'data: {"type":"tool_call","tool_calls":[{"id":"c1","name":"get_time","arguments":{"timezone":"UTC"}}]}\n\n',
      ]);
      final chunks = await parseSseChunks(stream).toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.isToolCall, isTrue);
      expect(chunks.single.toolCalls?.single.name, 'get_time');
    });
  });
}
