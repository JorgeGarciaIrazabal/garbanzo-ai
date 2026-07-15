import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_recorder.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_tts_queue.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_vad.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';

/// Phases of a hands-free voice turn.
enum TalkPhase {
  /// Waiting for the user to start a call.
  idle,

  /// Microphone is open; VAD listens for the user to speak (and stop).
  listening,

  /// Captured audio is being transcribed (STT).
  transcribing,

  /// The model is generating a reply that isn't speakable yet.
  thinking,

  /// The reply is being spoken back.
  speaking,

  /// A recoverable error occurred; a short message is shown.
  error,
}

/// Drives Talk Mode: a small state machine over the existing chat turn.
///
/// Reuses [ChatProvider] for the LLM turn (so memory, KB, and tools keep
/// working), [TalkRecorder] + [TalkVad] for hands-free capture, and
/// [TalkTtsQueue] for speaking the reply sentence-by-sentence as it streams.
///
/// Flow once a call is started (first tap): listen → VAD detects the user
/// stopped → transcribe → send → speak the reply → loop back to listening.
/// A tap interrupts the current phase and the ✕ button ends the call.
///
/// [voiceBargeIn] (auto-interrupt by talking over the AI) is enabled, but only
/// takes effect when the recorder reports **active echo cancellation** (the
/// PipeWire echo-cancel source on Linux, or hardware AEC on mobile). Without
/// AEC the mic hears the AI's own playback and no energy threshold can tell
/// "the AI is loud" from "the user is talking over it", so barge-in stays off
/// there to avoid self-interruption. Tap-to-interrupt always works.
class TalkModeController extends ChangeNotifier {
  TalkModeController({
    required ChatProvider chat,
    required SettingsProvider settings,
    bool voiceBargeIn = true,
  }) : _chat = chat,
       _settings = settings,
       _voiceBargeIn = voiceBargeIn {
    _prevSending = _chat.isSending;
    _chat.addListener(_onChatChanged);
  }

  final ChatProvider _chat;
  final SettingsProvider _settings;
  final TalkRecorder _recorder = TalkRecorder();
  final TalkVad _vad = TalkVad();

  /// When true, keep the mic open during the reply and auto-interrupt if the
  /// user talks over the AI. Tap-to-interrupt works regardless.
  final bool _voiceBargeIn;

  // Barge-in: interrupt when the user talks over the AI. The threshold is
  // relative to the learned ambient floor (like speech detection) but with a
  // wider margin so the AI's own playback echo doesn't self-trigger — the user
  // has to speak up over the AI. Requires several consecutive loud samples.
  static const double _bargeMarginDb = 14;
  static const int _bargeSustainSamples = 3; // ~300 ms at a 100 ms interval
  int _bargeLoud = 0;

  TalkTtsQueue? _tts;

  /// How many characters of the current reply have already been queued for
  /// speech, so streaming updates only enqueue the newly-completed remainder.
  int _spokenUpTo = 0;
  bool _streamFinished = false;

  /// True between the first tap (start call) and ending it (✕ / interrupt to
  /// idle). Drives the listen→speak→listen loop.
  bool _callActive = false;
  bool get isCallActive => _callActive;

  /// When muted, the mic stays closed and the listen loop parks in
  /// [TalkPhase.listening] without capturing until the user unmutes.
  bool _muted = false;
  bool get isMuted => _muted;

  TalkPhase _phase = TalkPhase.idle;
  TalkPhase get phase => _phase;

  /// Normalized mic level (0..1) for the visualizer; only meaningful while
  /// [TalkPhase.listening].
  double _level = 0;
  double get level => _level;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// What STT heard in the user's last utterance — shown as a live caption so
  /// mis-transcriptions are visible instead of silently producing a bad turn.
  String _userTranscript = '';
  String get userTranscript => _userTranscript;

  /// The assistant's reply text as it streams in (kept after the turn ends so
  /// the caption stays readable while the user speaks again).
  String _assistantText = '';
  String get assistantText => _assistantText;

  bool _prevSending = false;
  bool _awaitingReply = false;
  bool _disposed = false;
  Timer? _retryTimer;

  /// Whether talking over the AI can interrupt it (needs echo cancellation —
  /// see the class doc). Drives the status hint while speaking.
  bool get bargeInAvailable =>
      _voiceBargeIn && !_muted && _recorder.echoCancellationActive;

  /// Human-readable status line for the UI.
  String get statusText => switch (_phase) {
    TalkPhase.idle => 'Tap to start',
    TalkPhase.listening => _muted ? 'Muted' : 'Listening…',
    TalkPhase.transcribing => 'Transcribing…',
    TalkPhase.thinking => 'Thinking…',
    TalkPhase.speaking =>
      bargeInAvailable
          ? 'Speaking… talk or tap to interrupt'
          : 'Speaking… tap to interrupt',
    TalkPhase.error => _errorMessage ?? 'Something went wrong',
  };

  /// Toggle the microphone. Muting closes the mic immediately in whatever
  /// phase it was open for — the listening capture or the barge-in monitor
  /// during a reply. Unmuting resumes capture only while listening; mid-reply
  /// the barge mic stays off until the next listen re-arms it.
  Future<void> toggleMute() async {
    _muted = !_muted;
    if (_muted) {
      _recorder.dispose();
      _level = 0;
      notifyListeners();
    } else if (_phase == TalkPhase.listening) {
      await _startListening();
    } else {
      notifyListeners();
    }
  }

  /// Central tap handler — meaning depends on the current phase.
  Future<void> onTap() async {
    switch (_phase) {
      case TalkPhase.idle:
      case TalkPhase.error:
        if (!_callActive) {
          // Fresh call — clear captions from the previous one.
          _userTranscript = '';
          _assistantText = '';
        }
        _callActive = true;
        await _startListening();
      case TalkPhase.listening:
        await _stopAndSend(); // manual send without waiting for VAD
      case TalkPhase.thinking:
      case TalkPhase.speaking:
        await _interrupt();
      case TalkPhase.transcribing:
        break; // busy — ignore taps
    }
  }

  Future<void> _startListening() async {
    _retryTimer?.cancel();
    _errorMessage = null;
    _vad.reset();
    _level = 0;
    // Muted: park in listening with the mic closed until the user unmutes.
    if (_muted) {
      _setPhase(TalkPhase.listening);
      return;
    }
    try {
      await _recorder.start(onDb: _onDb);
      _setPhase(TalkPhase.listening);
    } catch (e) {
      _fail('Microphone unavailable: $e');
    }
  }

  /// Amplitude sample from the recorder. Its meaning depends on the phase:
  /// while listening it drives VAD + the visualizer; while the AI is *speaking*
  /// it watches for the user talking over it (voice barge-in). Barge-in is not
  /// armed during `thinking` (nothing is playing yet, so ambient noise
  /// shouldn't cancel the request).
  void _onDb(double db) {
    switch (_phase) {
      case TalkPhase.listening:
        if (_muted) return;
        _level = ((db + 60) / 60).clamp(0.0, 1.0);
        if (_vad.update(db, DateTime.now()) == VadEvent.speechEnd) {
          unawaited(_stopAndSend());
        } else {
          notifyListeners(); // refresh the visualizer level
        }
      case TalkPhase.speaking:
        if (!_muted) _detectBargeIn(db);
      case TalkPhase.thinking:
      case TalkPhase.idle:
      case TalkPhase.transcribing:
      case TalkPhase.error:
        break;
    }
  }

  /// Interrupt the AI once the user has been loud for a sustained stretch,
  /// measured relative to the ambient floor the VAD learned while listening.
  void _detectBargeIn(double db) {
    if (db > _vad.noiseFloorDb + _bargeMarginDb) {
      if (++_bargeLoud >= _bargeSustainSamples) {
        _bargeLoud = 0;
        unawaited(_interrupt(carryOverCapture: true));
      }
    } else {
      _bargeLoud = 0;
    }
  }

  Future<void> _stopAndSend() async {
    _setPhase(TalkPhase.transcribing);
    _level = 0;
    String? transcript;
    try {
      final result = await _recorder.stopAndTranscribe();
      transcript = result?.transcript.trim();
    } catch (e) {
      _fail('Could not transcribe: ${_brief(e)}', recoverable: true);
      return;
    }

    if (transcript == null || transcript.isEmpty) {
      // Nothing heard — resume listening so the call keeps going.
      await _resumeListeningOrIdle();
      return;
    }

    _userTranscript = transcript;
    _beginReply();
    _setPhase(TalkPhase.thinking);
    await _chat.sendMessage(transcript);
    _prevSending = _chat.isSending;
  }

  /// Arm a fresh reply: TTS queue + streaming subscription for live speech,
  /// plus (optionally) the barge-in mic so the user can talk over the AI.
  void _beginReply() {
    _spokenUpTo = 0;
    _streamFinished = false;
    _awaitingReply = true;
    _bargeLoud = 0;
    _assistantText = '';
    _tts = TalkTtsQueue(
      voice: _settings.ttsVoice,
      speed: _settings.ttsSpeed,
      onComplete: _onQueueDrained,
    );
    _chat.streamingMessage.addListener(_onStreamingContent);
    // Keep the mic open during the reply for voice barge-in — but only when
    // echo cancellation is active, otherwise the AI's own playback would
    // self-trigger an interrupt.
    if (_voiceBargeIn && !_muted && _recorder.echoCancellationActive) {
      unawaited(
        _recorder
            .start(onDb: _onDb)
            .catchError(
              (Object e) => logDebug('TalkMode: barge mic failed: $e'),
            ),
      );
    }
  }

  /// Speak each newly-completed sentence as the reply streams in, and mirror
  /// the full text into [assistantText] for the live caption.
  void _onStreamingContent() {
    final content = _chat.streamingMessage.value?.content ?? '';
    // The notifier clears to null at stream end — keep the last caption.
    if (content.isNotEmpty && content != _assistantText) {
      _assistantText = content;
      notifyListeners();
    }
    final cut = lastSentenceBoundary(content, _spokenUpTo);
    if (cut <= _spokenUpTo) return;
    _tts?.enqueue(content.substring(_spokenUpTo, cut));
    _spokenUpTo = cut;
    if (_phase == TalkPhase.thinking) _setPhase(TalkPhase.speaking);
  }

  /// Reacts to the chat turn finishing (isSending true → false).
  void _onChatChanged() {
    final sending = _chat.isSending;
    if (_prevSending && !sending && _awaitingReply) {
      _awaitingReply = false;
      _finishReply();
    }
    _prevSending = sending;
  }

  /// Stream ended: flush the trailing partial sentence and settle the phase.
  void _finishReply() {
    _streamFinished = true;
    _chat.streamingMessage.removeListener(_onStreamingContent);

    // streamingMessage is cleared by the time the turn ends, so read the
    // committed final text from the message list.
    final full = _lastAssistantContent() ?? '';
    if (full.isNotEmpty) _assistantText = full;
    if (full.length > _spokenUpTo) {
      _tts?.enqueue(full.substring(_spokenUpTo));
      _spokenUpTo = full.length;
    }

    // If nothing is (or will be) speaking, the turn is over immediately.
    if (_tts == null || !_tts!.isSpeaking) unawaited(_endSpeaking());
  }

  /// TTS queue drained. Only ends the turn once the stream has also finished —
  /// mid-stream drains just wait for the next sentence.
  void _onQueueDrained() {
    if (_streamFinished) unawaited(_endSpeaking());
  }

  Future<void> _endSpeaking() async {
    _tts = null;
    _spokenUpTo = 0;
    if (_phase == TalkPhase.thinking || _phase == TalkPhase.speaking) {
      await _resumeListeningOrIdle();
    }
  }

  /// Loop back to listening while the call is active; otherwise settle to idle.
  Future<void> _resumeListeningOrIdle() async {
    if (_callActive) {
      await _startListening();
    } else {
      _setPhase(TalkPhase.idle);
    }
  }

  /// Stop the AI's turn (playback + stream). With [carryOverCapture] — used by
  /// voice barge-in — the already-running barge mic keeps capturing across the
  /// transition so the words that *triggered* the interrupt aren't lost: the
  /// buffer is trimmed to the last couple of seconds (the reply-period echo
  /// isn't worth transcribing) and the VAD is pre-armed as mid-speech.
  Future<void> _interrupt({bool carryOverCapture = false}) async {
    _awaitingReply = false;
    _streamFinished = true;
    _chat.streamingMessage.removeListener(_onStreamingContent);
    await _tts?.stop();
    _tts = null;
    _spokenUpTo = 0;
    if (_chat.isSending) await _chat.stopStreaming();

    if (carryOverCapture &&
        _callActive &&
        !_muted &&
        _recorder.supportsCarryOver) {
      _recorder.trimBufferToLast(const Duration(seconds: 2));
      _vad
        ..reset()
        ..forceSpeaking(DateTime.now());
      _errorMessage = null;
      _setPhase(TalkPhase.listening);
      return;
    }
    // A tap barge-in during the AI's turn drops straight back to listening.
    await _resumeListeningOrIdle();
  }

  /// End the call entirely: stop capture/playback and return to idle.
  Future<void> endCall() async {
    _callActive = false;
    _retryTimer?.cancel();
    _awaitingReply = false;
    _streamFinished = true;
    _chat.streamingMessage.removeListener(_onStreamingContent);
    _recorder.dispose();
    await _tts?.stop();
    _tts = null;
    if (_chat.isSending) await _chat.stopStreaming();
    _setPhase(TalkPhase.idle);
  }

  /// Last index (exclusive) up to which [content] holds complete sentences,
  /// i.e. just past the final sentence-terminator followed by whitespace.
  @visibleForTesting
  static int lastSentenceBoundary(String content, int from) {
    var cut = from;
    for (final m in RegExp(r'[.!?]\s').allMatches(content)) {
      final boundary = m.start + 1; // right after the punctuation
      if (boundary > from) cut = boundary;
    }
    return cut;
  }

  String? _lastAssistantContent() {
    for (final msg in _chat.messages.reversed) {
      if (msg.isAssistant) return msg.content;
    }
    return null;
  }

  /// Enter the error phase. [recoverable] failures during an active call
  /// auto-resume listening after a short pause, so a transient hiccup (an STT
  /// timeout, say) doesn't strand a hands-free call waiting for a tap.
  /// Non-recoverable ones (mic unavailable) stay parked until the user taps.
  void _fail(String message, {bool recoverable = false}) {
    logDebug('TalkMode: $message');
    _errorMessage = message;
    _setPhase(TalkPhase.error);
    if (recoverable && _callActive) {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 2), () {
        if (!_disposed && _callActive && _phase == TalkPhase.error) {
          unawaited(_startListening());
        }
      });
    }
  }

  /// First ~120 chars of an exception, single line, for the status display.
  static String _brief(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    return s.length > 120 ? '${s.substring(0, 117)}…' : s;
  }

  void _setPhase(TalkPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _callActive = false;
    _retryTimer?.cancel();
    _chat.removeListener(_onChatChanged);
    _chat.streamingMessage.removeListener(_onStreamingContent);
    _recorder.shutdown(); // stops capture and unloads the AEC module
    _tts?.stop();
    super.dispose();
  }
}
