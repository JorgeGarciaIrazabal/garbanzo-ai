import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'package:garbanzo_ai/features/chat/services/read_aloud_service.dart';

enum ListeningState {
  idle,
  preparing,
  playing,
  paused,
  buffering,
  completed,
  failed,
}

/// Narrow player interface makes lifecycle and stale-response behaviour
/// testable without an Android audio decoder.
abstract class ReadAloudPlayer {
  Stream<Duration> get positions;
  Stream<ja.PlayerState> get states;
  Stream<ja.PlaybackEvent> get errors;
  Duration get position;
  ja.PlayerState get currentState;
  Future<void> setUrl(Uri uri, Map<String, String> headers);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class JustAudioReadAloudPlayer implements ReadAloudPlayer {
  JustAudioReadAloudPlayer()
    : _player = ja.AudioPlayer(useProxyForRequestHeaders: false);

  final ja.AudioPlayer _player;
  @override
  Stream<Duration> get positions => _player.positionStream;
  @override
  Stream<ja.PlayerState> get states => _player.playerStateStream;
  @override
  Stream<ja.PlaybackEvent> get errors => _player.playbackEventStream;
  @override
  Duration get position => _player.position;
  @override
  ja.PlayerState get currentState => _player.playerState;
  @override
  Future<void> setUrl(Uri uri, Map<String, String> headers) async {
    await _player.setUrl(uri.toString(), headers: headers);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  Future<void> dispose() => _player.dispose();
}

class ReadAloudController extends ChangeNotifier with WidgetsBindingObserver {
  ReadAloudController({
    ReadAloudService? service,
    ReadAloudPlayer? player,
    DateTime Function()? now,
  }) : _service = service ?? ReadAloudService(),
       _player = player ?? JustAudioReadAloudPlayer(),
       _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    _positions = _player.positions.listen(_onPosition);
    _states = _player.states.listen(_onPlayerState);
    _errors = _player.errors.listen(
      (_) {},
      onError: (Object error) {
        if (_session != null) _fail(error);
      },
    );
    _watchdog = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkProgress(),
    );
  }

  final ReadAloudService _service;
  final ReadAloudPlayer _player;
  final DateTime Function() _now;
  late final StreamSubscription<Duration> _positions;
  late final StreamSubscription<ja.PlayerState> _states;
  late final StreamSubscription<ja.PlaybackEvent> _errors;
  late final Timer _watchdog;
  StreamSubscription<void>? _events;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _wantsPlay = false;
  bool _audioReady = false;
  bool _previewing = false;
  String? _previewVoiceId;
  int _offsetMs = 0;
  int _stablePositionMs = 0;
  int _lastReportedMs = 0;
  int _reportSeq = 0;
  int _lastProgressMs = 0;
  DateTime _lastProgressAt = DateTime.now();
  DateTime _playbackAnchorAt = DateTime.now();
  int _playbackAnchorMs = 0;
  ReadAloudSession? _session;
  String? _text;
  String? _messageId;
  String? _voiceEn;
  String? _voiceEs;
  String _languageMode = 'auto';
  ListeningState _state = ListeningState.idle;
  String? _error;
  double _speed = 1.0;

  ListeningState get state => _state;
  String? get error => _error;
  String? get messageId => _messageId;
  String? get activePreviewVoiceId => _previewVoiceId;
  String? get text => _text;
  ReadAloudSession? get session => _session;
  double get speed => _speed;
  int get positionMs => _stablePositionMs;
  int get generatedDurationMs => _session?.generatedDurationMs ?? 0;
  int get totalParagraphs => _session?.totalParagraphs ?? 0;
  bool get active => _state != ListeningState.idle;
  bool get canStop => active;

  int get currentParagraph {
    final segments = _session?.segments ?? const <ReadAloudSegment>[];
    if (segments.isEmpty) return 0;
    var paragraph = segments.first.paragraph;
    for (final segment in segments) {
      if (segment.startMs > positionMs) break;
      paragraph = segment.paragraph;
    }
    return paragraph;
  }

  List<int> get preparedParagraphs {
    final paragraphs = <int>{};
    for (final segment in _session?.segments ?? const <ReadAloudSegment>[]) {
      paragraphs.add(segment.paragraph);
    }
    return paragraphs.toList()..sort();
  }

  Future<void> start({
    required String messageId,
    required String text,
    required String voiceEn,
    required String voiceEs,
    required double speed,
    String languageMode = 'auto',
    int startParagraph = 0,
  }) async {
    // Invalidate all pending network/player callbacks before touching the old
    // session. The new request can then be cancelled even before POST returns.
    final serial = ++_generation;
    final oldId = _session?.id;
    _session = null;
    _audioReady = false;
    _offsetMs = 0;
    _stablePositionMs = 0;
    _lastReportedMs = 0;
    _reportSeq = 0;
    _lastProgressMs = 0;
    _lastProgressAt = _now();
    _playbackAnchorAt = _now();
    _playbackAnchorMs = 0;
    _previewing = false;
    _previewVoiceId = null;
    _messageId = messageId;
    _text = text;
    _voiceEn = voiceEn;
    _voiceEs = voiceEs;
    _languageMode = languageMode;
    _speed = speed;
    _error = null;
    _wantsPlay = _foreground;
    _state = ListeningState.preparing;
    notifyListeners();
    unawaited(_events?.cancel());
    _events = null;
    final stopped = _player.stop();
    if (oldId != null) {
      unawaited(_service.cancel(oldId).catchError((Object _) {}));
    }

    try {
      final created = await _service.create(
        text: text,
        voiceEn: voiceEn,
        voiceEs: voiceEs,
        languageMode: languageMode,
        startParagraph: startParagraph,
      );
      if (!_isCurrent(serial)) {
        unawaited(_service.cancel(created.id).catchError((Object _) {}));
        return;
      }
      _session = created;
      notifyListeners();
      _listenEvents(created.id, serial);
      await stopped;
      if (!_isCurrent(serial)) return;
      await _openAudio(created.id, serial, 0);
    } catch (error) {
      if (_isCurrent(serial)) _fail(error);
    }
  }

  void _listenEvents(String id, int serial) {
    _events = _service
        .events(id)
        .listen(
          (_) async {
            if (!_isCurrent(serial)) return;
            try {
              final updated = await _service.status(id);
              if (!_isCurrent(serial)) return;
              _session = updated;
              notifyListeners();
              if (updated.state == 'failed' ||
                  updated.state == 'expired' ||
                  updated.state == 'cancelled') {
                _fail(
                  ReadAloudException(
                    0,
                    updated.error ??
                        'Speech generation stopped. Retry from this paragraph.',
                  ),
                );
              }
            } catch (error) {
              if (_isCurrent(serial)) _fail(error);
            }
          },
          onError: (Object error) {
            if (_isCurrent(serial)) _fail(error);
          },
          onDone: () async {
            if (!_isCurrent(serial) || _state == ListeningState.failed) return;
            try {
              final updated = await _service.status(id);
              if (!_isCurrent(serial)) return;
              _session = updated;
              notifyListeners();
              if (updated.state == 'failed' ||
                  updated.state == 'expired' ||
                  updated.state == 'cancelled') {
                _fail(
                  ReadAloudException(
                    0,
                    updated.error ??
                        'Speech generation stopped. Retry from this paragraph.',
                  ),
                );
              } else if (updated.state != 'completed') {
                _fail(
                  const ReadAloudException(
                    0,
                    'Connection to speech generation was lost. Retry from this paragraph.',
                  ),
                );
              }
            } catch (error) {
              if (_isCurrent(serial)) _fail(error);
            }
          },
        );
  }

  Future<void> _openAudio(String id, int serial, int segmentIndex) async {
    try {
      final request = await _service.audioRequest(
        id,
        startSegment: segmentIndex,
      );
      if (!_isCurrent(serial)) return;
      await _player.setUrl(request.uri, request.headers);
      if (!_isCurrent(serial)) return;
      await _player.setSpeed(_speed);
      if (!_isCurrent(serial)) return;
      _playbackAnchorAt = _now();
      _playbackAnchorMs = 0;
      _audioReady = true;
      if (_wantsPlay && _foreground) {
        _state = ListeningState.playing;
        notifyListeners();
        unawaited(
          _player.play().catchError((Object error) {
            if (_isCurrent(serial)) _fail(error);
          }),
        );
        unawaited(_report('playing'));
      } else {
        _state = ListeningState.paused;
        notifyListeners();
        unawaited(_report('paused'));
      }
    } catch (error) {
      if (_isCurrent(serial)) _fail(error);
    }
  }

  Future<void> pause() async {
    if (!active || _state == ListeningState.completed) return;
    _wantsPlay = false;
    _state = ListeningState.paused;
    notifyListeners();
    if (_audioReady) await _player.pause();
    unawaited(_report('paused'));
  }

  Future<void> resume() async {
    if (_state != ListeningState.paused || !_foreground) return;
    _wantsPlay = true;
    if (!_audioReady) {
      _state = ListeningState.preparing;
      notifyListeners();
      return;
    }
    _state = ListeningState.playing;
    _anchorPlaybackClock();
    notifyListeners();
    final serial = _generation;
    unawaited(
      _player.play().catchError((Object error) {
        if (_isCurrent(serial)) _fail(error);
      }),
    );
    unawaited(_report('playing'));
  }

  Future<void> stop() async {
    final oldId = _session?.id;
    ++_generation;
    _session = null;
    _messageId = null;
    _text = null;
    _wantsPlay = false;
    _audioReady = false;
    _previewing = false;
    _previewVoiceId = null;
    _error = null;
    _state = ListeningState.idle;
    notifyListeners();
    unawaited(_events?.cancel());
    _events = null;
    await _player.stop();
    if (oldId != null) await _service.cancel(oldId);
  }

  Future<void> jumpToParagraph(int paragraph) async {
    final session = _session;
    if (session == null) return;
    final segments = session.segments.where((s) => s.paragraph == paragraph);
    if (segments.isEmpty) return;
    final first = segments.first;
    final serial = ++_generation;
    _wantsPlay = _foreground && _wantsPlay;
    unawaited(_events?.cancel());
    _listenEvents(session.id, serial);
    _offsetMs = first.startMs;
    _stablePositionMs = first.startMs;
    _lastReportedMs = first.startMs;
    _lastProgressMs = first.startMs;
    _lastProgressAt = _now();
    _playbackAnchorAt = _now();
    _playbackAnchorMs = 0;
    _audioReady = false;
    _state = ListeningState.preparing;
    notifyListeners();
    await _player.stop();
    if (!_isCurrent(serial)) return;
    await _openAudio(session.id, serial, first.index);
  }

  Future<void> nextParagraph() async {
    for (final paragraph in preparedParagraphs) {
      if (paragraph > currentParagraph) {
        await jumpToParagraph(paragraph);
        return;
      }
    }
  }

  Future<void> previousParagraph() async {
    final preceding = preparedParagraphs.where((p) => p < currentParagraph);
    await jumpToParagraph(
      preceding.isEmpty ? currentParagraph : preceding.last,
    );
  }

  Future<void> replay() async {
    final paragraphs = preparedParagraphs;
    if (paragraphs.isNotEmpty) {
      _wantsPlay = _foreground;
      await jumpToParagraph(paragraphs.first);
    }
  }

  Future<void> retryFromParagraph() async {
    final text = _text;
    final messageId = _messageId;
    final voiceEn = _voiceEn;
    final voiceEs = _voiceEs;
    if (text == null ||
        messageId == null ||
        voiceEn == null ||
        voiceEs == null) {
      return;
    }
    await start(
      messageId: messageId,
      text: text,
      voiceEn: voiceEn,
      voiceEs: voiceEs,
      speed: _speed,
      languageMode: _languageMode,
      startParagraph: currentParagraph,
    );
  }

  Future<void> setSpeed(double speed) async {
    _anchorPlaybackClock();
    _speed = speed.clamp(0.5, 2.0);
    notifyListeners();
    await _player.setSpeed(_speed);
  }

  Future<void> previewVoice(String voiceId) async {
    await stop();
    _previewing = true;
    _previewVoiceId = voiceId;
    _wantsPlay = _foreground;
    _audioReady = false;
    final serial = ++_generation;
    _state = ListeningState.preparing;
    notifyListeners();
    try {
      final request = await _service.previewRequest(voiceId);
      if (!_isCurrent(serial)) return;
      await _player.setUrl(request.uri, request.headers);
      if (!_isCurrent(serial)) return;
      _audioReady = true;
      _state = _wantsPlay && _foreground
          ? ListeningState.playing
          : ListeningState.paused;
      notifyListeners();
      if (_wantsPlay && _foreground) {
        unawaited(
          _player.play().catchError((Object error) {
            if (_isCurrent(serial)) _fail(error);
          }),
        );
      }
    } catch (error) {
      if (_isCurrent(serial)) _fail(error);
    }
  }

  void _onPosition(Duration position) {
    if (_session == null || _disposed || !_audioReady) return;
    final playerMs = _player.position.inMilliseconds;
    final eventMs = position.inMilliseconds;
    // Queued position events from a stopped source can arrive after a switch.
    // Accept only events consistent with the currently loaded player source.
    if (eventMs < 0 || (eventMs - playerMs).abs() > 250) return;
    final acceptedMs = _stablePositionMs - _offsetMs;
    if (eventMs + 250 < acceptedMs) return;
    final elapsedMs = _now().difference(_playbackAnchorAt).inMilliseconds;
    final maxExpectedMs = _wantsPlay
        ? _playbackAnchorMs + elapsedMs.clamp(0, 1 << 31) * _speed + 1500
        : acceptedMs + 250;
    if (eventMs > maxExpectedMs) return;
    final absolute = _offsetMs + eventMs;
    _stablePositionMs = absolute;
    if (absolute > _lastProgressMs) {
      _lastProgressMs = absolute;
      _lastProgressAt = _now();
    }
    notifyListeners();
    if (absolute - _lastReportedMs >= 5000) {
      _lastReportedMs = absolute;
      unawaited(
        _report(_state == ListeningState.playing ? 'playing' : 'paused'),
      );
    }
  }

  void _anchorPlaybackClock() {
    _playbackAnchorAt = _now();
    _playbackAnchorMs = (_stablePositionMs - _offsetMs).clamp(0, 1 << 31);
  }

  void _checkProgress() {
    if (_disposed ||
        _session == null ||
        !_wantsPlay ||
        (_state != ListeningState.playing &&
            _state != ListeningState.buffering &&
            _state != ListeningState.preparing)) {
      return;
    }
    final idle = _now().difference(_lastProgressAt);
    if (_session!.state == 'completed' &&
        generatedDurationMs > 0 &&
        positionMs >= generatedDurationMs - 150 &&
        idle >= const Duration(seconds: 2)) {
      _complete();
    } else if (idle >= const Duration(seconds: 15)) {
      _fail(
        const ReadAloudException(
          0,
          'Playback stopped making progress. Retry from this paragraph.',
        ),
      );
    }
  }

  void _complete() {
    if (_state == ListeningState.completed) return;
    _wantsPlay = false;
    _state = ListeningState.completed;
    notifyListeners();
    if (_session != null) unawaited(_report('completed'));
  }

  void _onPlayerState(ja.PlayerState state) {
    if (_disposed || !_audioReady || (!_previewing && _session == null)) return;
    final current = _player.currentState;
    if (current.processingState != state.processingState ||
        current.playing != state.playing) {
      return;
    }
    if (state.processingState == ja.ProcessingState.completed) {
      if (_previewing ||
          (_session?.state == 'completed' &&
              generatedDurationMs > 0 &&
              positionMs >= generatedDurationMs - 250 &&
              _wantsPlay)) {
        _complete();
      }
    } else if (state.processingState == ja.ProcessingState.buffering &&
        _wantsPlay) {
      _state = ListeningState.buffering;
      notifyListeners();
      if (_session != null) unawaited(_report('buffering'));
    } else if (state.playing &&
        _wantsPlay &&
        _state != ListeningState.playing) {
      _state = ListeningState.playing;
      notifyListeners();
    }
  }

  Future<void> _report(String state) async {
    final id = _session?.id;
    if (id == null) return;
    final position = positionMs;
    final seq = ++_reportSeq;
    final generation = _generation;
    try {
      await _service.update(id, state, position, seq);
    } catch (error) {
      // The backend uses position to bound synthesis ahead of playback. If
      // updates stop reaching it, continuing locally would eventually stall.
      // A superseded request may fail after a newer position was sent (or
      // after a seek changed the source); it cannot invalidate that source.
      if (_session?.id == id &&
          generation == _generation &&
          seq == _reportSeq &&
          _state != ListeningState.failed) {
        _fail(error);
      }
    }
  }

  void _fail(Object error) {
    if (_state == ListeningState.failed || _disposed) return;
    ++_generation;
    unawaited(_events?.cancel());
    _events = null;
    _wantsPlay = false;
    _error = switch (error) {
      ReadAloudException(:final statusCode) when statusCode == 401 =>
        'Your session expired. Sign in again to listen.',
      ReadAloudException(:final statusCode) when statusCode == 410 =>
        'This listening session expired. Retry from this paragraph.',
      _ => error.toString(),
    };
    _state = ListeningState.failed;
    notifyListeners();
    unawaited(_player.stop());
    final id = _session?.id;
    if (id != null) unawaited(_service.cancel(id).catchError((Object _) {}));
  }

  bool _isCurrent(int serial) => !_disposed && serial == _generation;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground &&
        active &&
        _state != ListeningState.completed &&
        _state != ListeningState.failed) {
      unawaited(pause());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _watchdog.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_positions.cancel());
    unawaited(_states.cancel());
    unawaited(_errors.cancel());
    unawaited(_events?.cancel());
    unawaited(_player.stop());
    unawaited(_player.dispose());
    final id = _session?.id;
    if (id != null) unawaited(_service.cancel(id).catchError((Object _) {}));
    super.dispose();
  }
}
