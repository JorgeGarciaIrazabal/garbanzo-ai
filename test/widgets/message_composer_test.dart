import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
);

void main() {
  testWidgets('phone composer stays to two compact rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
          leading: const IconButton(
            key: ValueKey('phone_attach'),
            onPressed: null,
            icon: Icon(Icons.add),
          ),
          bottomToolbar: Row(
            children: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.post_add)),
              const Expanded(
                child: Text('Super fast', overflow: TextOverflow.ellipsis),
              ),
              const ActionChip(label: Text('High'), onPressed: null),
              IconButton(onPressed: () {}, icon: const Icon(Icons.layers)),
            ],
          ),
          idleTrailingBuilder: (_) => const IconButton(
            key: ValueKey('phone_mic'),
            onPressed: null,
            icon: Icon(Icons.mic),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('message_composer_surface')), findsOneWidget);
    expect(find.text('Super fast'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    final inputCenter = tester.getCenter(
      find.byKey(const ValueKey('message_input')),
    );
    final attachCenter = tester.getCenter(
      find.byKey(const ValueKey('phone_attach')),
    );
    final micCenter = tester.getCenter(find.byKey(const ValueKey('phone_mic')));
    expect((inputCenter.dy - attachCenter.dy).abs(), lessThan(1));
    expect((inputCenter.dy - micCenter.dy).abs(), lessThan(1));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('message_composer_surface')))
          .height,
      lessThanOrEqualTo(120),
    );
  });

  testWidgets('composer focus gets a clear primary affordance', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        MessageComposer(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) {},
        ),
      ),
    );

    final before = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('message_composer_surface')),
    );
    final beforeDecoration = before.decoration! as BoxDecoration;

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();

    final after = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('message_composer_surface')),
    );
    final afterDecoration = after.decoration! as BoxDecoration;
    expect(afterDecoration.border, isNot(equals(beforeDecoration.border)));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide window with a 508px chat pane uses compact toolbar layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 508,
            child: MessageComposer(
              controller: controller,
              focusNode: focusNode,
              onSend: (_) {},
              leading: const IconButton(
                key: ValueKey('local_attach'),
                onPressed: null,
                icon: Icon(Icons.add),
              ),
              bottomToolbar: Row(
                key: const ValueKey('local_toolbar'),
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.post_add),
                  ),
                  const Expanded(
                    child: Text('Brainstorm', overflow: TextOverflow.ellipsis),
                  ),
                  const ActionChip(label: Text('High'), onPressed: null),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.layers),
                  ),
                ],
              ),
              idleTrailingBuilder: (_) => const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: null, icon: Icon(Icons.mic)),
                  IconButton(onPressed: null, icon: Icon(Icons.graphic_eq)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final toolbarTop = tester.getTopLeft(
      find.byKey(const ValueKey('local_toolbar')),
    );
    final attachCenter = tester.getCenter(
      find.byKey(const ValueKey('local_attach')),
    );
    final inputCenter = tester.getCenter(
      find.byKey(const ValueKey('message_input')),
    );
    expect((attachCenter.dy - inputCenter.dy).abs(), lessThan(1));
    expect(toolbarTop.dy, greaterThan(inputCenter.dy));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('message_composer_surface')))
          .height,
      lessThanOrEqualTo(120),
    );
  });

  testWidgets('wide composer also rests on one input line', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 820,
          child: MessageComposer(
            controller: controller,
            focusNode: focusNode,
            onSend: (_) {},
            bottomToolbar: const Text('Composer settings'),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('message_input')),
    );
    expect(field.minLines, 1);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('message_composer_surface')))
          .height,
      lessThanOrEqualTo(110),
    );
    expect(tester.takeException(), isNull);
  });
}
