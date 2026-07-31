import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_audio_note_player.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

class _FakeSource extends Fake implements Source {}

void main() {
  const note = RoomAudioNote(
    id: 'note-1',
    mimeType: 'audio/wav',
    durationSeconds: 5,
  );

  setUpAll(() => registerFallbackValue(_FakeSource()));

  Widget app(
    RoomAudioLoader loader, {
    AudioPlayer Function()? playerFactory,
  }) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: RoomAudioNotePlayer(
        roomId: 'room-1',
        note: note,
        loader: loader,
        playerFactory: playerFactory,
      ),
    ),
  );

  testWidgets('audio bytes are loaded lazily on the first play', (tester) async {
    var calls = 0;
    Future<Uint8List> loader(String roomId, String noteId) async {
      calls++;
      throw Exception('offline');
    }

    await tester.pumpWidget(app(loader));
    expect(calls, 0);
    expect(find.text('0:00 / 0:05'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('audio_note_play_note-1')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Could not load the audio note'), findsOneWidget);
  });

  testWidgets('a completed audio note can be played a second time', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final player = _MockAudioPlayer();
    final completed = StreamController<void>();
    when(() => player.onPositionChanged).thenAnswer((_) => const Stream.empty());
    when(() => player.onPlayerComplete).thenAnswer((_) => completed.stream);
    when(
      () => player.play(any(), position: any(named: 'position')),
    ).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});

    await tester.pumpWidget(
      app(
        (_, _) async => Uint8List.fromList([1, 2, 3]),
        playerFactory: () => player,
      ),
    );

    final playButton = find.byKey(
      const ValueKey('audio_note_play_note-1'),
    );
    await tester.tap(playButton);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    completed.add(null);
    await tester.pump();
    await tester.tap(playButton);
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;

    verify(
      () => player.play(any(), position: Duration.zero),
    ).called(2);

    await completed.close();
  });

  testWidgets('playback speed cycles through 1x, 1.5x, and 2x', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final player = _MockAudioPlayer();
    when(() => player.onPositionChanged).thenAnswer((_) => const Stream.empty());
    when(() => player.onPlayerComplete).thenAnswer((_) => const Stream.empty());
    when(
      () => player.play(any(), position: any(named: 'position')),
    ).thenAnswer((_) async {});
    when(() => player.setPlaybackRate(any())).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});

    await tester.pumpWidget(
      app(
        (_, _) async => Uint8List.fromList([1, 2, 3]),
        playerFactory: () => player,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('audio_note_play_note-1')),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    final speedButton = find.byKey(
      const ValueKey('audio_note_speed_note-1'),
    );
    expect(find.text('1x'), findsOneWidget);

    await tester.tap(speedButton);
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);

    await tester.tap(speedButton);
    await tester.pump();
    expect(find.text('2x'), findsOneWidget);

    await tester.tap(speedButton);
    await tester.pump();
    expect(find.text('1x'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;

    verifyInOrder([
      () => player.setPlaybackRate(1.5),
      () => player.setPlaybackRate(2.0),
      () => player.setPlaybackRate(1.0),
    ]);
  });
}
