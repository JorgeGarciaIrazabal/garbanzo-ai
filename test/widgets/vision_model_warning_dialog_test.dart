import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/vision_model_warning_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

ModelInfo _model(String id) => ModelInfo(
  id: id,
  name: id,
  provider: 'ollama',
  supportsVision: true,
);

void main() {
  Widget app(List<VisionModelChoice> choices) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<VisionModelChoice>(
            context: context,
            builder: (_) => VisionModelWarningDialog(
              currentModelName: 'Text Model',
              choices: choices,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );

  testWidgets('presents fast and smart choices as a warning, not an error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app([
        VisionModelChoice(
          model: _model(ModelProvider.fastVisionModelId),
          kind: VisionModelChoiceKind.faster,
        ),
        VisionModelChoice(
          model: _model(ModelProvider.smartVisionModelId),
          kind: VisionModelChoiceKind.smarter,
        ),
      ]),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Choose a Vision model'), findsOneWidget);
    expect(find.text('GLM 5.3 Flash'), findsOneWidget);
    expect(find.text('Faster · lower cost · Cloud'), findsOneWidget);
    expect(find.text('Kimi K3'), findsOneWidget);
    expect(find.text('Smarter · higher cost · Cloud'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns the selected model choice', (tester) async {
    final smart = VisionModelChoice(
      model: _model(ModelProvider.smartVisionModelId),
      kind: VisionModelChoiceKind.smarter,
    );
    VisionModelChoice? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<VisionModelChoice>(
                  context: context,
                  builder: (_) => VisionModelWarningDialog(
                    currentModelName: 'Text Model',
                    choices: [smart],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('vision_model_choice_kimi-k3:cloud')),
    );
    await tester.pumpAndSettle();

    expect(result, same(smart));
  });
}
