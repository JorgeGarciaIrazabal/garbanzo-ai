import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_tts_queue.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';

/// Phases of a hands-free voice turn.
enum TalkPhase {
  /// Waiting for the user to start a turn.
  idle,

  /// Microphone is capturing the user's speech.
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
/// It reuses [ChatProvider] for the actual LLM turn (so memory, KB, and tools
/// keep working), [VoiceRecordingHelper] for STT capture, and [TalkTtsQueue]
/// for speaking the reply. The reply is spoken **sentence-by-sentence as it
/// streams** — each completed sentence in [ChatProvider.streamingMessage] is
/// enqueued immediately, so speech starts on the first sentence instead of
/// waiting for the whole answer. While the model reasons (thinking chunks or
/// no speakable text yet) the phase stays [TalkPhase.thinking].
///
/// Phase 1/2 are tap-driven: tap to talk, tap again to send. VAD auto
/// start/stop and voice barge-in arrive in later phases.
class TalkModeController extends ChangeNotifier {
  TalkModeController({
    required ChatProvider chat,
    required SettingsProvider settings,
  }) : _chat = chat,
       _settings = settings {
    _prevSending = _chat.isSending;
    _chat.addListener(_onChatChanged);
  }

  final ChatProvider _chat;
  final SettingsProvider _settings;
  final VoiceRecordingHelper _recorder = VoiceRecordingHelper();

  TalkTtsQueue? _tts;

  /// How many characters of the current reply have already been queued for
  /// speech, so streaming updates only enqueue the newly-completed remainder.
  int _spokenUpTo = 0;
  bool _streamFinished = false;

  TalkPhase _phase = TalkPhase.idle;
  TalkPhase get phase => _phase;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _prevSending = false;
  bool _awaitingReply = false;
  bool _disposed = false;

  /// Human-readable status line for the UI.
  String get statusText => switch (_phase) {
    TalkPhase.idle => 'Tap to talk',
    TalkPhase.listening => 'Listening… tap to send',
    TalkPhase.transcribing => 'Transcribing…',
    TalkPhase.thinking => 'Thinking…',
    TalkPhase.speaking => 'Speaking… tap to interrupt',
    TalkPhase.error => _errorMessage ?? 'Something went wrong',
  };

  /// Central tap handler — meaning depends on the current phase.
  Future<void> onTap() async {
    switch (_phase) {
      case TalkPhase.idle:
      case TalkPhase.error:
        await _startListening();
      case TalkPhase.listening:
        await _stopAndSend();
      case TalkPhase.thinking:
      case TalkPhase.speaking:
        await _interrupt();
      case TalkPhase.transcribing:
        break; // busy — ignore taps
    }
  }

  Future<void> _startListening() async {
    _errorMessage = null;
    try {
      await _recorder.startRecording();
      _setPhase(TalkPhase.listening);
    } catch (e) {
      _fail('Microphone unavailable: $e');
    }
  }

  Future<void> _stopAndSend() async {
    _setPhase(TalkPhase.transcribing);
    String? transcript;
    try {
      final result = await _recorder.stopAndTranscribe();
      transcript = result?.transcript.trim();
    } catch (e) {
      _fail('Could not transcribe: $e');
      return;
    }

    if (transcript == null || transcript.isEmpty) {
      // Nothing heard — quietly return to idle so the user can retry.
      _setPhase(TalkPhase.idle);
      return;
    }

    _beginReply();
    _setPhase(TalkPhase.thinking);
    await _chat.sendMessage(transcript);
    _prevSending = _chat.isSending;
  }

  /// Arm a fresh reply: TTS queue + streaming subscription for live speech.
  void _beginReply() {
    _spokenUpTo = 0;
    _streamFinished = false;
    _awaitingReply = true;
    _tts = TalkTtsQueue(
      voice: _settings.ttsVoice,
      speed: _settings.ttsSpeed,
      onComplete: _onQueueDrained,
    );
    _chat.streamingMessage.addListener(_onStreamingContent);
  }

  /// Speak each newly-completed sentence as the reply streams in.
  void _onStreamingContent() {
    final content = _chat.streamingMessage.value?.content ?? '';
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
    if (full.length > _spokenUpTo) {
      _tts?.enqueue(full.substring(_spokenUpTo));
      _spokenUpTo = full.length;
    }

    // If nothing is (or will be) speaking, the turn is over immediately.
    if (_tts == null || !_tts!.isSpeaking) _endSpeaking();
  }

  /// TTS queue drained. Only ends the turn once the stream has also finished —
  /// mid-stream drains just wait for the next sentence.
  void _onQueueDrained() {
    if (_streamFinished) _endSpeaking();
  }

  void _endSpeaking() {
    _tts = null;
    _spokenUpTo = 0;
    if (_phase == TalkPhase.thinking || _phase == TalkPhase.speaking) {
      _setPhase(TalkPhase.idle);
    }
  }

  Future<void> _interrupt() async {
    _awaitingReply = false;
    _streamFinished = true;
    _chat.streamingMessage.removeListener(_onStreamingContent);
    await _tts?.stop();
    _tts = null;
    _spokenUpTo = 0;
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

  void _fail(String message) {
    logDebug('TalkMode: $message');
    _errorMessage = message;
    _setPhase(TalkPhase.error);
  }

  void _setPhase(TalkPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _chat.removeListener(_onChatChanged);
    _chat.streamingMessage.removeListener(_onStreamingContent);
    _recorder.dispose();
    _tts?.stop();
    super.dispose();
  }
}
