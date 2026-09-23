import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Opens the app-scoped listening session for this message. Playback outlives
/// the message widget when it scrolls out of view.
class SpeakButton extends StatefulWidget {
  const SpeakButton({
    super.key,
    required this.content,
    this.messageId,
    this.isStreaming = false,
  });

  final String content;
  final String? messageId;
  final bool isStreaming;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  String? _openMenuMessageId;
  String get _id => widget.messageId ?? widget.content.hashCode.toString();

  @override
  void didUpdateWidget(SpeakButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isStreaming &&
        !widget.isStreaming &&
        widget.content.isNotEmpty) {
      final settings = context.read<SettingsProvider>();
      if (settings.autoPlayTts && !settings.talkModeActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _start();
        });
      }
    }
  }

  void _start() {
    if (kIsWeb) return;
    final settings = context.read<SettingsProvider>();
    unawaited(
      context.read<ReadAloudController>().start(
        messageId: _id,
        text: widget.content,
        voiceEn: settings.readAloudVoiceEn,
        voiceEs: settings.readAloudVoiceEs,
        speed: settings.ttsSpeed,
        languageMode: settings.readAloudLanguageMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReadAloudController>();
    final isActive = controller.messageId == _id && controller.active;
    final l10n = AppLocalizations.of(context)!;
    final state = controller.state;
    final label = !isActive
        ? l10n.readAloudListen
        : switch (state) {
            ListeningState.preparing => l10n.readAloudPreparingShort,
            ListeningState.playing => l10n.readAloudPlaying,
            ListeningState.paused => l10n.readAloudPaused,
            ListeningState.buffering => l10n.readAloudBuffering,
            ListeningState.completed => l10n.readAloudReplayShort,
            ListeningState.failed => l10n.readAloudRetryShort,
            ListeningState.idle => l10n.readAloudListen,
          };
    final icon = !isActive
        ? Icons.volume_up
        : switch (state) {
            ListeningState.preparing ||
            ListeningState.buffering => Icons.hourglass_top,
            ListeningState.playing => Icons.graphic_eq,
            ListeningState.paused => Icons.play_arrow,
            ListeningState.completed => Icons.replay,
            ListeningState.failed => Icons.refresh,
            ListeningState.idle => Icons.volume_up,
          };
    void onTap() {
      if (!isActive) {
        _start();
      } else {
        switch (state) {
          case ListeningState.preparing:
          case ListeningState.playing:
          case ListeningState.buffering:
            unawaited(controller.pause());
          case ListeningState.paused:
            unawaited(controller.resume());
          case ListeningState.completed:
            unawaited(controller.replay());
          case ListeningState.failed:
            unawaited(controller.retryFromParagraph());
          case ListeningState.idle:
            _start();
        }
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MessageActionButton(
          key: const ValueKey('speak_button'),
          icon: icon,
          label: label,
          tooltip: kIsWeb
              ? l10n.readAloudWebUnavailable
              : isActive
              ? switch (state) {
                  ListeningState.paused => l10n.readAloudResume,
                  ListeningState.completed => l10n.readAloudReplay,
                  ListeningState.failed => l10n.readAloudRetry,
                  _ => l10n.readAloudPause,
                }
              : l10n.readAloudListenTooltip,
          highlighted: isActive,
          onTap: kIsWeb ? null : onTap,
        ),
        if (isActive && !kIsWeb)
          PopupMenuButton<_ReadAloudAction>(
            key: const ValueKey('read_aloud_more'),
            tooltip: l10n.readAloudMoreControls,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 200),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            onOpened: () => _openMenuMessageId = _id,
            onCanceled: () => _openMenuMessageId = null,
            onSelected: (action) {
              final menuMessageId = _openMenuMessageId;
              _openMenuMessageId = null;
              if (!controller.active ||
                  menuMessageId == null ||
                  controller.messageId != menuMessageId) {
                return;
              }
              switch (action) {
                case _ReadAloudAction.previous:
                  unawaited(controller.previousParagraph());
                case _ReadAloudAction.next:
                  unawaited(controller.nextParagraph());
                case _ReadAloudAction.retry:
                  unawaited(controller.retryFromParagraph());
                case _ReadAloudAction.stop:
                  unawaited(controller.stop());
              }
            },
            itemBuilder: (context) {
              final prepared = controller.preparedParagraphs;
              final paragraph = controller.currentParagraph;
              return [
                if (controller.totalParagraphs > 0)
                  PopupMenuItem<_ReadAloudAction>(
                    enabled: false,
                    child: Text(
                      l10n.readAloudParagraph(
                        paragraph + 1,
                        controller.totalParagraphs,
                      ),
                    ),
                  ),
                if (state == ListeningState.failed)
                  PopupMenuItem<_ReadAloudAction>(
                    enabled: false,
                    child: Text(
                      controller.error ?? l10n.readAloudFailed,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                PopupMenuItem(
                  key: const ValueKey('read_aloud_previous'),
                  value: _ReadAloudAction.previous,
                  enabled: prepared.any((p) => p < paragraph),
                  child: Text(l10n.readAloudPrevious),
                ),
                PopupMenuItem(
                  key: const ValueKey('read_aloud_next'),
                  value: _ReadAloudAction.next,
                  enabled: prepared.any((p) => p > paragraph),
                  child: Text(l10n.readAloudNext),
                ),
                if (state == ListeningState.failed)
                  PopupMenuItem(
                    key: const ValueKey('read_aloud_retry'),
                    value: _ReadAloudAction.retry,
                    child: Text(l10n.readAloudRetry),
                  ),
                PopupMenuItem(
                  key: const ValueKey('read_aloud_stop'),
                  value: _ReadAloudAction.stop,
                  child: Text(l10n.readAloudStop),
                ),
              ];
            },
          ),
        if (isActive && !kIsWeb) ReadAloudMessageControls(messageId: _id),
      ],
    );
  }
}

enum _ReadAloudAction { previous, next, retry, stop }

/// Circular speed control next to the active message's Listen button.
class ReadAloudMessageControls extends StatelessWidget {
  const ReadAloudMessageControls({super.key, required this.messageId});

  final String messageId;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final listening = context.watch<ReadAloudController>();
    if (kIsWeb || !listening.active || listening.messageId != messageId) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: '${l10n.titleSpeed}: ${_speedLabel(listening.speed)}',
      child: InkWell(
        key: const ValueKey('read_aloud_speed'),
        customBorder: const CircleBorder(),
        onTap: () {
          if (!listening.active || listening.messageId != messageId) return;
          final current = _speeds.indexWhere(
            (s) => (s - listening.speed).abs() < 0.01,
          );
          final next = _speeds[(current + 1) % _speeds.length];
          unawaited(listening.setSpeed(next));
          unawaited(context.read<SettingsProvider>().setTtsSpeed(next));
        },
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              child: Text(
                _speedLabel(listening.speed),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _speedLabel(double speed) {
    final value = speed.toStringAsFixed(2);
    return '${value.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}×';
  }
}
