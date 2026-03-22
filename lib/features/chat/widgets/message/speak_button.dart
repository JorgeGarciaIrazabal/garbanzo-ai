import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../settings/providers/settings_provider.dart';
import '../../services/audio_service.dart';
import '../../utils/text_cleaner.dart';

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

  @override
  void didUpdateWidget(SpeakButton old) {
    super.didUpdateWidget(old);
    // Auto-play: when streaming transitions from true → false
    if (old.isStreaming && !widget.isStreaming && widget.content.isNotEmpty) {
      final settings = context.read<SettingsProvider>();
      if (settings.autoPlayTts) {
        _speak();
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _player?.dispose();
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
      if (cleaned.isEmpty) return;

      final chunks = _splitIntoChunks(cleaned);

      // Fire ALL requests up-front so the backend queues them back-to-back.
      final futures = chunks
          .map((c) => AudioService.instance
              .speak(c, voice: settings.ttsVoice, speed: settings.ttsSpeed))
          .toList();

      for (int i = 0; i < futures.length; i++) {
        if (_cancelled) break;

        final audioBytes = await futures[i];
        if (_cancelled) break;

        // Fresh player per chunk — reusing the same player for sequential
        // play() calls is unreliable across platforms (web, Android, Linux).
        _player?.dispose();
        _player = AudioPlayer();

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

        await _player!.play(BytesSource(audioBytes));
        await completer.future;
      }

      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech synthesis failed: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    _cancelled = true;
    await _player?.stop();
    if (mounted) {
      setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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

    return InkWell(
      onTap: _isPlaying ? _stop : _speak,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying ? Icons.stop : Icons.volume_up,
              size: 14,
              color: _isPlaying
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              _isPlaying ? 'Stop' : 'Listen',
              style: TextStyle(
                fontSize: 12,
                color: _isPlaying
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
