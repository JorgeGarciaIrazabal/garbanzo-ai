import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/services/tts_audio_source.dart';
import 'package:garbanzo_ai/features/chat/utils/text_cleaner.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';

/// Speak button for TTS playback of assistant messages.
///
/// Reads voice/speed from [SettingsProvider] and cleans markdown/emojis
/// before synthesis. Supports auto-play when streaming finishes.
class SpeakButton extends StatefulWidget {
  const SpeakButton({
    super.key,
    required this.content,
    this.isStreaming = false,
  });

  final String content;
  final bool isStreaming;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _cancelled = false;
  AudioPlayer? _player;
  PreparedTtsAudioSource? _audioSource;

  @override
  void didUpdateWidget(SpeakButton old) {
    super.didUpdateWidget(old);
    // Auto-play: when streaming transitions from true → false. Suppressed while
    // Talk Mode is open — it speaks the reply itself, and a second playback here
    // would overlap the same text offset by the streaming lead.
    if (old.isStreaming && !widget.isStreaming && widget.content.isNotEmpty) {
      final settings = context.read<SettingsProvider>();
      if (settings.autoPlayTts && !settings.talkModeActive) {
        _speak();
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_releasePlayback());
    super.dispose();
  }

  /// Split text into chunks (~500 chars) at sentence boundaries.
  static List<String> _splitIntoChunks(String text) {
    const targetSize = 500;
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      if (buf.length + trimmed.length > targetSize && buf.isNotEmpty) {
        chunks.add(buf.toString().trim());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(trimmed);
    }
    if (buf.isNotEmpty) chunks.add(buf.toString().trim());
    return chunks.isEmpty ? [text] : chunks;
  }

  Future<void> _speak() async {
    setState(() {
      _isLoading = true;
      _cancelled = false;
    });

    try {
      final settings = context.read<SettingsProvider>();
      final cleaned = cleanTextForSpeech(widget.content);
      if (cleaned.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final chunks = _splitIntoChunks(cleaned);

      // Fire ALL requests up-front so the backend queues them back-to-back.
      final futures = chunks
          .map(
            (c) => AudioService.instance.speak(
              c,
              voice: settings.ttsVoice,
              speed: settings.ttsSpeed,
            ),
          )
          .toList();

      for (int i = 0; i < futures.length; i++) {
        if (_cancelled) break;

        final audioBytes = await futures[i];
        if (_cancelled) break;

        // Fresh player per chunk — reusing the same player for sequential
        // play() calls is unreliable across platforms (web, Android, Linux).
        await _releasePlayback();
        final source = await prepareTtsAudioSource(audioBytes, format: 'mp3');
        if (_cancelled) {
          await source.dispose();
          break;
        }
        final player = AudioPlayer();
        _player = player;
        _audioSource = source;

        if (i == 0 && mounted) {
          setState(() {
            _isPlaying = true;
            _isLoading = false;
          });
        }

        final completer = Completer<void>();
        _player!.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _player!.play(_audioSource!.source);
        await completer.future;
      }

      await _releasePlayback();

      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } catch (e) {
      await _releasePlayback();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
        final message =
            e.toString().contains('500') || e.toString().contains('unavailable')
            ? 'Text-to-speech is currently unavailable'
            : 'Speech synthesis failed: $e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _stop() async {
    _cancelled = true;
    await _player?.stop();
    await _releasePlayback();
    if (mounted) {
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _releasePlayback() async {
    final player = _player;
    final source = _audioSource;
    _player = null;
    _audioSource = null;
    await player?.dispose();
    await source?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(4),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return MessageActionButton(
      key: const ValueKey('speak_button'),
      icon: _isPlaying ? Icons.stop : Icons.volume_up,
      label: _isPlaying ? 'Stop' : 'Listen',
      tooltip: _isPlaying ? 'Stop playback' : 'Read this message aloud',
      highlighted: _isPlaying,
      onTap: _isPlaying ? _stop : _speak,
    );
  }
}
