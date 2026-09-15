import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/clipboard_image_reader.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
);

/// Presses Ctrl+V on the focused composer, the real user shortcut.
Future<void> _pressPaste(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  tearDown(() => ClipboardImageReader.debugOverride = null);

  testWidgets('a pasted clipboard image is staged as an attachment', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    ClipboardImageReader.debugOverride = () async => [
      (name: 'pasted_20260101_120000.png', bytes: bytes),
    ];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    List<ClipboardImage>? pasted;

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
          onPasteImage: (images) => pasted = images,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();
    await _pressPaste(tester);

    expect(pasted, isNotNull);
    expect(pasted, hasLength(1));
    expect(pasted!.single.name, 'pasted_20260101_120000.png');
    expect(pasted!.single.bytes, bytes);
    // The image must not also be pasted as text/path into the message.
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paste falls back to text when the clipboard has no image', (
    tester,
  ) async {
    ClipboardImageReader.debugOverride = () async => const [];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var pastedImages = 0;

    // Stand in for the platform text clipboard.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'hi from clipboard'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
          onPasteImage: (images) => pastedImages += images.length,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();
    await _pressPaste(tester);

    expect(controller.text, 'hi from clipboard');
    expect(pastedImages, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a composer without the paste hook keeps plain text pasting', (
    tester,
  ) async {
    ClipboardImageReader.debugOverride = () async => [
      (name: 'pasted.png', bytes: Uint8List.fromList([1, 2, 3])),
    ];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'plain'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();
    await _pressPaste(tester);

    expect(controller.text, 'plain');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an image pasted before the field is disabled is not staged', (
    tester,
  ) async {
    ClipboardImageReader.debugOverride = () async => [
      (name: 'pasted.png', bytes: Uint8List.fromList([1, 2, 3])),
    ];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var staged = 0;

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
          enabled: false,
          onPasteImage: (images) => staged += images.length,
        ),
      ),
    );

    await _pressPaste(tester);

    expect(staged, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a clipboard read that never returns still pastes text', (
    tester,
  ) async {
    // A clipboard whose promise never completes must not wedge the composer:
    // the read is budgeted, so text pasting still gets its turn.
    final stuck = Completer<List<ClipboardImage>>();
    ClipboardImageReader.debugOverride = () => stuck.future;
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'text won'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
          onPasteImage: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();
    await _pressPaste(tester);
    // Release the stuck read so the pending paste can finish.
    stuck.complete(const []);
    await tester.pump();

    expect(controller.text, 'text won');
    expect(tester.takeException(), isNull);
  });
}
