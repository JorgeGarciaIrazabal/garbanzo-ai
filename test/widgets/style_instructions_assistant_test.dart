import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/style_instructions_assistant.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class _Prompts extends SystemPromptProvider {
  final calls = <Map<String, String?>>[];
  final streams = <StreamController<ChatResponseChunk>>[];
  int canceled = 0;

  @override
  Future<void> refresh({String? locale}) async {}

  @override
  Stream<ChatResponseChunk> generateInstructions({
    required String intent,
    String? existingPrompt,
    String? feedback,
    required String model,
  }) {
    calls.add({'intent': intent, 'existing': existingPrompt, 'feedback': feedback, 'model': model});
    final stream = StreamController<ChatResponseChunk>(onCancel: () { canceled++; });
    streams.add(stream);
    return stream.stream;
  }
}

void main() {
  late _Prompts prompts;
  late TextEditingController instructions;
  late List<bool> pending;

  setUp(() {
    prompts = _Prompts();
    instructions = TextEditingController();
    pending = [];
  });

  tearDown(() {
    for (final stream in prompts.streams) { unawaited(stream.close()); }
    prompts.dispose();
    instructions.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: StyleInstructionsAssistant(
        controller: instructions,
        prompts: prompts,
        modelId: 'chosen-model',
        enabled: true,
        onPendingChanged: pending.add,
      ))),
    ));
    await tester.tap(find.byKey(const ValueKey('style_ai_help')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('style_ai_request')), 'A patient tutor');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('style_ai_generate')));
    await tester.pump();
  }

  testWidgets('generate previews streamed instructions and applies only on accept', (tester) async {
    await mount(tester);
    expect(prompts.calls.single, {'intent': 'A patient tutor', 'existing': null, 'feedback': null, 'model': 'chosen-model'});
    prompts.streams.single.add(const ChatResponseChunk(type: 'thinking', content: 'hidden reasoning'));
    prompts.streams.single.add(const ChatResponseChunk(type: 'chunk', content: 'Teach with examples.'));
    await tester.pump();
    expect(instructions.text, isEmpty);
    expect(find.text('hidden reasoning'), findsNothing);
    expect(pending.last, true);
    prompts.streams.single.add(const ChatResponseChunk(type: 'done'));
    await tester.pumpAndSettle();
    expect(instructions.text, isEmpty);
    await tester.tap(find.byKey(const ValueKey('style_ai_accept')));
    await tester.pumpAndSettle();
    expect(instructions.text, 'Teach with examples.');
    expect(pending.last, false);
  });

  testWidgets('enhance passes current draft and feedback; discard preserves edits', (tester) async {
    instructions.text = 'My manually edited instructions';
    await mount(tester);
    expect(prompts.calls.single['existing'], instructions.text);
    expect(prompts.calls.single['feedback'], 'A patient tutor');
    prompts.streams.single.add(const ChatResponseChunk(type: 'chunk', content: 'A different draft'));
    prompts.streams.single.add(const ChatResponseChunk(type: 'done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('style_ai_discard')));
    await tester.pumpAndSettle();
    expect(instructions.text, 'My manually edited instructions');
    expect(pending.last, false);
  });

  testWidgets('cancel stops stream and cannot replace original instructions', (tester) async {
    instructions.text = 'Keep me';
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('style_ai_discard')));
    await tester.pumpAndSettle();
    prompts.streams.single.add(const ChatResponseChunk(type: 'chunk', content: 'Late result'));
    prompts.streams.single.add(const ChatResponseChunk(type: 'done'));
    await tester.pumpAndSettle();
    expect(prompts.canceled, 1);
    expect(instructions.text, 'Keep me');
    expect(find.byKey(const ValueKey('style_ai_accept')), findsNothing);
    expect(pending.last, false);
  });

  for (final failure in ['error', 'disconnect', 'empty', 'transport']) {
    testWidgets('$failure preserves draft and allows retry', (tester) async {
      instructions.text = 'Keep me';
      await mount(tester);
      if (failure != 'empty') {
        prompts.streams.single.add(const ChatResponseChunk(type: 'chunk', content: 'Partial'));
      }
      if (failure == 'error') {
        prompts.streams.single.add(const ChatResponseChunk(type: 'error', error: 'Failed'));
      } else if (failure == 'disconnect') {
        unawaited(prompts.streams.single.close());
      } else if (failure == 'transport') {
        prompts.streams.single.addError(Exception('Disconnected'));
      } else {
        prompts.streams.single.add(const ChatResponseChunk(type: 'done'));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('style_ai_error')), findsOneWidget);
      expect(find.byKey(const ValueKey('style_ai_accept')), findsNothing);
      expect(instructions.text, 'Keep me');
      expect(pending.last, false);
      await tester.tap(find.byKey(const ValueKey('style_ai_generate')));
      await tester.pump();
      expect(prompts.calls, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('disposing cancels generation without touching instructions', (tester) async {
    instructions.text = 'Keep me';
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    expect(prompts.canceled, 1);
    expect(instructions.text, 'Keep me');
  });
}
