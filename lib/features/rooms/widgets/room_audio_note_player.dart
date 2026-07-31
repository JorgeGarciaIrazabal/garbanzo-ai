import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/services/tts_audio_source.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

typedef RoomAudioLoader =
    Future<Uint8List> Function(String roomId, String noteId);

class RoomAudioNotePlayer extends StatefulWidget {
  const RoomAudioNotePlayer({
    super.key,
    required this.roomId,
    required this.note,
    this.loader,
    this.playerFactory,
  });

  final String roomId;
  final RoomAudioNote note;
  final RoomAudioLoader? loader;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @override
  State<RoomAudioNotePlayer> createState() => _RoomAudioNotePlayerState();
}

class _RoomAudioNotePlayerState extends State<RoomAudioNotePlayer> {
  static const _playbackRates = [1.0, 1.5, 2.0];

  AudioPlayer? _player;
  PreparedTtsAudioSource? _source;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _completeSubscription;
  Duration _position = Duration.zero;
  bool _isLoading = false;
  bool _isPlaying = false;
  double _playbackRate = _playbackRates.first;

  Duration get _duration =>
      Duration(milliseconds: (widget.note.durationSeconds * 1000).round());

  Future<void> _toggle() async {
    if (_isLoading) return;
    if (_isPlaying) {
      await _player?.pause();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    try {
      if (_player == null) await _prepare();
      final position = _position >= _duration ? Duration.zero : _position;
      await _player?.play(_source!.source, position: position);
      if (_playbackRate != 1.0) {
        await _player?.setPlaybackRate(_playbackRate);
      }
      if (mounted) setState(() => _isPlaying = true);
    } catch (_) {
      await _release();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isPlaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.messageAudioNoteLoadFailed,
          ),
        ),
      );
    }
  }

  Future<void> _prepare() async {
    setState(() => _isLoading = true);
    final loader = widget.loader ?? RoomService.instance.loadAudioNote;
    final bytes = await loader(widget.roomId, widget.note.id);
    final source = await prepareTtsAudioSource(bytes, format: 'wav');
    final player = widget.playerFactory?.call() ?? AudioPlayer();
    _player = player;
    _source = source;
    _positionSubscription = player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _completeSubscription = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _position = _duration;
          _isPlaying = false;
        });
      }
    });
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _seek(double milliseconds) async {
    final position = Duration(milliseconds: milliseconds.round());
    setState(() => _position = position);
    await _player?.seek(position);
  }

  Future<void> _cyclePlaybackRate() async {
    final currentIndex = _playbackRates.indexOf(_playbackRate);
    final nextRate = _playbackRates[(currentIndex + 1) % _playbackRates.length];
    setState(() => _playbackRate = nextRate);
    await _player?.setPlaybackRate(nextRate);
  }

  String get _playbackRateLabel {
    final rate = _playbackRate;
    return rate == rate.roundToDouble()
        ? rate.toInt().toString()
        : rate.toStringAsFixed(1);
  }

  Future<void> _release() async {
    await _positionSubscription?.cancel();
    await _completeSubscription?.cancel();
    _positionSubscription = null;
    _completeSubscription = null;
    final player = _player;
    final source = _source;
    _player = null;
    _source = null;
    await player?.dispose();
    await source?.dispose();
  }

  @override
  void dispose() {
    unawaited(_release());
    super.dispose();
  }

  String _format(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final durationMs = _duration.inMilliseconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    final positionMs = _position.inMilliseconds
        .toDouble()
        .clamp(0, durationMs)
        .toDouble();
    return Semantics(
      label: AppLocalizations.of(context)!.labelAudioNote,
      child: Row(
        children: [
          IconButton.filledTonal(
            key: ValueKey('audio_note_play_${widget.note.id}'),
            onPressed: _toggle,
            tooltip: _isPlaying
                ? AppLocalizations.of(context)!.labelPause
                : AppLocalizations.of(context)!.labelPlay,
            icon: _isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Slider(
              value: positionMs,
              max: durationMs,
              onChanged: _player == null ? null : _seek,
            ),
          ),
          Text(
            '${_format(_position)} / ${_format(_duration)}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          TextButton(
            key: ValueKey('audio_note_speed_${widget.note.id}'),
            onPressed: _cyclePlaybackRate,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Tooltip(
              message: AppLocalizations.of(context)!.titleSpeed,
              child: Text(
                AppLocalizations.of(context)!.ttsSpeedValue(_playbackRateLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
