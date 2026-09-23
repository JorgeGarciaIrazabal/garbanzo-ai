import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/speak_button.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Listening extends ChangeNotifier implements ReadAloudController {
  String _messageId = 'message-1';
  ListeningState _state = ListeningState.playing;
  double _speed = 1.0;
  int stopCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int retryCalls = 0;

  @override
  String? get messageId => _messageId;
  @override
  bool get active => _state != ListeningState.idle;
  @override
  ListeningState get state => _state;
  @override
  int get currentParagraph => 0;
  @override
  int get totalParagraphs => 3;
  @override
  List<int> get preparedParagraphs => const [0, 1];
  @override
  String? get error => _state == ListeningState.failed
      ? 'The connection stopped while preparing this paragraph.'
      : null;
  @override
  double get speed => _speed;

  @override
  Future<void> pause() async {
    pauseCalls++;
    _state = ListeningState.paused;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    _state = ListeningState.playing;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _state = ListeningState.idle;
    notifyListeners();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
  }

  @override
  Future<void> retryFromParagraph() async {
    retryCalls++;
    _state = ListeningState.preparing;
    notifyListeners();
  }

  void fail() {
    _state = ListeningState.failed;
    notifyListeners();
  }

  void activateOtherMessage() {
    _messageId = 'message-2';
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _Listening listening, {
  ValueNotifier<String>? messageId,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final settings = SettingsProvider();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ReadAloudController>.value(value: listening),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (messageId == null)
                const SpeakButton(
                  content: 'Test message.',
                  messageId: 'message-1',
                )
              else
                ValueListenableBuilder<String>(
                  valueListenable: messageId,
                  builder: (context, id, _) => SpeakButton(
                    content: 'Test message.',
                    messageId: id,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speaking button pauses, resumes, cycles speed and offers Stop', (tester) async {
    final listening = _Listening();
    await _pump(tester, listening);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('read_aloud_speed')), findsOneWidget);
    expect(find.byKey(const ValueKey('read_aloud_more')), findsOneWidget);
    expect(find.byKey(const ValueKey('read_aloud_stop')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('read_aloud_speed'))).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(const ValueKey('read_aloud_more'))).width, greaterThanOrEqualTo(48));

    await tester.tap(find.byKey(const ValueKey('speak_button')));
    await tester.pump();
    expect(listening.pauseCalls, 1);
    expect(find.text('En pausa'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('speak_button')));
    await tester.pump();
    expect(listening.resumeCalls, 1);
    await tester.tap(find.byKey(const ValueKey('read_aloud_speed')));
    await tester.pump();
    expect(listening.speed, 1.25);
    expect(find.text('1.25×'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('read_aloud_more')));
    await tester.pumpAndSettle();
    expect(find.text('Párrafo 1 de 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('read_aloud_stop')));
    await tester.pumpAndSettle();
    expect(listening.stopCalls, 1);
    expect(find.byKey(const ValueKey('read_aloud_stop')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old message menu cannot stop a newer session', (tester) async {
    final listening = _Listening();
    final messageId = ValueNotifier('message-1');
    await _pump(tester, listening, messageId: messageId);
    await tester.tap(find.byKey(const ValueKey('read_aloud_more')));
    await tester.pumpAndSettle();
    listening.activateOtherMessage();
    messageId.value = 'message-2';
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('read_aloud_stop')));
    await tester.pumpAndSettle();
    expect(listening.stopCalls, 0);
  });

  testWidgets('failed paragraph offers retry without narrow-screen overflow', (tester) async {
    final listening = _Listening()..fail();
    await _pump(tester, listening);
    expect(find.byKey(const ValueKey('read_aloud_retry')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('read_aloud_more')));
    await tester.pumpAndSettle();
    expect(find.textContaining('connection'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('read_aloud_retry')));
    await tester.pump();
    expect(listening.retryCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
