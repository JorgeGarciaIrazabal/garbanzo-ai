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
/// for speaking the reply. Phase 1 is tap-driven: tap to talk, tap again to
/// send; the final reply is spoken once the stream ends. VAD auto start/stop
/// and barge-in arrive in later phases.
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

    _awaitingReply = true;
    _setPhase(TalkPhase.thinking);
    await _chat.sendMessage(transcript);
    _prevSending = _chat.isSending;
  }

  Future<void> _interrupt() async {
    _awaitingReply = false;
    await _tts?.stop();
    _tts = null;
    if (_chat.isSending) {
      await _chat.stopStreaming();
    }
    _setPhase(TalkPhase.idle);
  }

  /// Reacts to the chat turn finishing: speak the final assistant reply.
  void _onChatChanged() {
    final sending = _chat.isSending;
    if (_prevSending && !sending && _awaitingReply) {
      _awaitingReply = false;
      _speakReply();
    }
    _prevSending = sending;
  }

  void _speakReply() {
    final reply = _lastAssistantContent();
    if (reply == null || reply.trim().isEmpty) {
      _setPhase(TalkPhase.idle);
      return;
    }
    _setPhase(TalkPhase.speaking);
    _tts = TalkTtsQueue(
      voice: _settings.ttsVoice,
      speed: _settings.ttsSpeed,
      onComplete: _onSpeakingDone,
    )..enqueue(reply);
  }

  void _onSpeakingDone() {
    _tts = null;
    if (_phase == TalkPhase.speaking) _setPhase(TalkPhase.idle);
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
    _recorder.dispose();
    _tts?.stop();
    super.dispose();
  }
}
