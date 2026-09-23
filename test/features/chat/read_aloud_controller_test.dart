import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/services/read_aloud_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

class _Service extends ReadAloudService {
  final pending = <Completer<ReadAloudSession>>[];
  final cancelled = <String>[];
  final starts = <int>[];
  final positionUpdates = <int>[];
  final reports = <({String id, String state, int position, int seq})>[];
  final heldReports = <Completer<void>>[];
  bool holdUpdates = false;
  final eventsController = StreamController<void>.broadcast();
  ReadAloudSession? current;

  @override
  Future<ReadAloudSession> create({
    required String text,
    required String voiceEn,
    required String voiceEs,
    String languageMode = 'auto',
    int startParagraph = 0,
  }) {
    starts.add(startParagraph);
    final completer = Completer<ReadAloudSession>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Future<ReadAloudSession> status(String id) async => current!;

  @override
  Stream<void> events(String id) => eventsController.stream;

  @override
  Future<({Uri uri, Map<String, String> headers})> audioRequest(
    String id, {
    int startSegment = 0,
  }) async => (
    uri: Uri.parse('https://example.test/audio?start_segment=$startSegment'),
    headers: {'Authorization': 'Bearer test'},
  );

  @override
  Future<({Uri uri, Map<String, String> headers})> previewRequest(String id) async => (
    uri: Uri.parse('https://example.test/voices/$id/preview'),
    headers: {'Authorization': 'Bearer test'},
  );

  @override
  Future<void> update(String id, String state, int positionMs, int updateSeq) async {
    positionUpdates.add(positionMs);
    reports.add((id: id, state: state, position: positionMs, seq: updateSeq));
    if (holdUpdates) {
      final held = Completer<void>();
      heldReports.add(held);
      await held.future;
    }
  }
}

class _Player implements ReadAloudPlayer {
  final stateEvents = StreamController<ja.PlayerState>.broadcast();
  final positionEvents = StreamController<Duration>.broadcast();
  final requested = <Uri>[];
  Duration currentPosition = Duration.zero;
  ja.PlayerState latestState = ja.PlayerState(false, ja.ProcessingState.idle);
  Completer<void>? blockSetUrl;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  @override
  Duration get position => currentPosition;
  @override
  ja.PlayerState get currentState => latestState;
  @override
  Stream<Duration> get positions => positionEvents.stream;
  @override
  Stream<ja.PlayerState> get states => stateEvents.stream;
  @override
  Stream<ja.PlaybackEvent> get errors => const Stream.empty();
  @override
  Future<void> setUrl(Uri uri, Map<String, String> headers) async {
    currentPosition = Duration.zero;
    latestState = ja.PlayerState(false, ja.ProcessingState.ready);
    requested.add(uri);
    expect(headers['Authorization'], 'Bearer test');
    await blockSetUrl?.future;
  }
  @override
  Future<void> play() async {
    playCalls++;
    latestState = ja.PlayerState(true, ja.ProcessingState.ready);
  }
  @override
  Future<void> pause() async {
    pauseCalls++;
    latestState = ja.PlayerState(false, ja.ProcessingState.ready);
  }
  @override
  Future<void> stop() async {
    stopCalls++;
    currentPosition = Duration.zero;
    latestState = ja.PlayerState(false, ja.ProcessingState.idle);
  }
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> dispose() async {
    await stateEvents.close();
    await positionEvents.close();
  }

  void advance(Duration position) {
    currentPosition = position;
    positionEvents.add(position);
  }

  void deliverOldPosition(Duration position) => positionEvents.add(position);

  void deliverOldState(ja.PlayerState state) => stateEvents.add(state);
}

ReadAloudSession _session(String id, {String state = 'preparing'}) =>
    ReadAloudSession(
      id: id,
      state: state,
      generatedDurationMs: 30000,
      positionMs: 0,
      totalParagraphs: 2,
      segments: const [
        ReadAloudSegment(id: 'a', index: 0, paragraph: 0, startMs: 0, durationMs: 10000),
        ReadAloudSegment(id: 'b', index: 1, paragraph: 1, startMs: 10000, durationMs: 20000),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stale creation is cancelled and never starts audio', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    final first = controller.start(
      messageId: 'first', text: 'First', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    final second = controller.start(
      messageId: 'second', text: 'Second', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending[1].complete(_session('second-session'));
    await second;
    service.pending[0].complete(_session('first-session'));
    await first;

    expect(controller.messageId, 'second');
    expect(player.requested, hasLength(1));
    expect(service.cancelled, contains('first-session'));
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('old player events after message switch cannot complete or advance new session', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    final first = controller.start(
      messageId: 'first', text: 'First', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('first-session', state: 'completed'));
    await first;
    final second = controller.start(
      messageId: 'second', text: 'Second', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.last.complete(_session('second-session', state: 'completed'));
    await second;
    // Some backends briefly expose the delayed value via their position
    // getter too, so equality with that getter alone is insufficient.
    player.currentPosition = const Duration(milliseconds: 29950);
    player.deliverOldPosition(const Duration(milliseconds: 29950));
    player.latestState = ja.PlayerState(true, ja.ProcessingState.completed);
    player.deliverOldState(ja.PlayerState(true, ja.ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(controller.messageId, 'second');
    expect(controller.state, ListeningState.playing);
    expect(controller.positionMs, 0);
    expect(service.reports.where((r) => r.id == 'second-session').every((r) => r.position == 0), isTrue);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('old player events after seek cannot change new source position or state', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session', state: 'completed'));
    await started;
    await controller.jumpToParagraph(1);
    await controller.jumpToParagraph(0);
    player.currentPosition = const Duration(milliseconds: 19950);
    player.deliverOldPosition(const Duration(milliseconds: 19950));
    player.latestState = ja.PlayerState(true, ja.ProcessingState.completed);
    player.deliverOldState(ja.PlayerState(true, ja.ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.playing);
    expect(controller.positionMs, 0);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('completion needs terminal generation and position near the current end', () async {
    final service = _Service();
    final player = _Player();
    var now = DateTime(2026);
    final controller = ReadAloudController(service: service, player: player, now: () => now);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session'));
    await started;
    player.latestState = ja.PlayerState(true, ja.ProcessingState.completed);
    player.deliverOldState(player.latestState);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.playing);

    service.current = _session('one-session', state: 'completed');
    service.eventsController.add(null);
    await Future<void>.delayed(Duration.zero);
    player.deliverOldState(player.latestState);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.playing);

    now = now.add(const Duration(seconds: 30));
    player.advance(const Duration(milliseconds: 29950));
    await Future<void>.delayed(Duration.zero);
    player.deliverOldState(player.latestState);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.completed);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('position PATCH captures increasing sequence across pause and seek', () async {
    final service = _Service();
    final player = _Player();
    var now = DateTime(2026);
    final controller = ReadAloudController(service: service, player: player, now: () => now);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session'));
    await started;
    service.holdUpdates = true;
    now = now.add(const Duration(seconds: 6));
    player.advance(const Duration(seconds: 6));
    await Future<void>.delayed(Duration.zero);
    await controller.pause();
    await controller.jumpToParagraph(1);
    await controller.resume();
    expect(service.reports.map((r) => r.seq), [1, 2, 3, 4, 5]);
    expect(service.reports.map((r) => (r.state, r.position)), [
      ('playing', 0),
      ('playing', 6000),
      ('paused', 6000),
      ('paused', 10000),
      ('playing', 10000),
    ]);
    for (final report in service.heldReports.reversed) {
      report.complete();
    }
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.playing);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('older PATCH failure after newer success does not fail playback', () async {
    final service = _Service();
    final player = _Player();
    var now = DateTime(2026);
    final controller = ReadAloudController(service: service, player: player, now: () => now);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session'));
    await started;
    service.holdUpdates = true;
    now = now.add(const Duration(seconds: 6));
    player.advance(const Duration(seconds: 6)); // seq 2
    await Future<void>.delayed(Duration.zero);
    await controller.pause(); // seq 3
    expect(service.heldReports, hasLength(2));
    service.heldReports[1].complete();
    await Future<void>.delayed(Duration.zero);
    service.heldReports[0].completeError(StateError('stale network failure'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.paused);
    expect(service.cancelled, isEmpty);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('latest PATCH failure still fails playback', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session'));
    await started;
    service.holdUpdates = true;
    await controller.pause();
    service.heldReports.single.completeError(StateError('current network failure'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.failed);
    expect(service.cancelled, contains('one-session'));
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('background pauses and foreground does not resume without a tap', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session'));
    await started;
    expect(player.playCalls, 1);

    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ListeningState.paused);
    expect(player.pauseCalls, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(player.playCalls, 1);
    await controller.resume();
    expect(player.playCalls, 2);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('stop during preparation cancels the eventual session', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    await controller.stop();
    expect(controller.state, ListeningState.idle);
    service.pending.single.complete(_session('late'));
    await started;
    expect(player.requested, isEmpty);
    expect(service.cancelled, contains('late'));
    controller.dispose();
    await service.eventsController.close();
  });

  test('position reports continue after jumping backward', () async {
    final service = _Service();
    final player = _Player();
    var now = DateTime(2026);
    final controller = ReadAloudController(service: service, player: player, now: () => now);
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session'));
    await started;
    await controller.jumpToParagraph(1);
    now = now.add(const Duration(seconds: 6));
    player.advance(const Duration(seconds: 6));
    await Future<void>.delayed(Duration.zero);
    expect(service.positionUpdates, contains(16000));
    await controller.jumpToParagraph(0);
    now = now.add(const Duration(seconds: 5));
    player.advance(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(service.positionUpdates, contains(5000));
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  test('voice preview pauses on background and waits for explicit resume', () async {
    final service = _Service();
    final player = _Player();
    final controller = ReadAloudController(service: service, player: player);
    await controller.previewVoice('alba');
    expect(controller.activePreviewVoiceId, 'alba');
    expect(player.playCalls, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);
    expect(player.pauseCalls, 1);
    expect(controller.state, ListeningState.paused);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(player.playCalls, 1);
    await controller.resume();
    expect(player.playCalls, 2);
    await controller.stop();
    expect(controller.activePreviewVoiceId, isNull);
    controller.dispose();
    await service.eventsController.close();
  });

  test('preview cannot begin playing after app backgrounds during preparation', () async {
    final service = _Service();
    final player = _Player()..blockSetUrl = Completer<void>();
    final controller = ReadAloudController(service: service, player: player);
    final preview = controller.previewVoice('lola');
    await Future<void>.delayed(Duration.zero);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    player.blockSetUrl!.complete();
    await preview;
    expect(player.playCalls, 0);
    expect(controller.state, ListeningState.paused);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });

  testWidgets('finishes near the end when player completion event is missing', (tester) async {
    final service = _Service();
    final player = _Player();
    var now = DateTime(2026);
    final controller = ReadAloudController(
      service: service,
      player: player,
      now: () => now,
    );
    final started = controller.start(
      messageId: 'one', text: 'Hello', voiceEn: 'alba', voiceEs: 'lola', speed: 1,
    );
    service.pending.single.complete(_session('one-session', state: 'completed'));
    await started;
    now = now.add(const Duration(seconds: 30));
    player.advance(const Duration(milliseconds: 29950));
    await tester.pump();
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(controller.state, ListeningState.completed);
    await controller.stop();
    controller.dispose();
    await service.eventsController.close();
  });
}
