import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/services/read_aloud_service.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Read-aloud preferences are independent of the Kokoro Talk Mode voice.
class ReadAloudVoiceSettings extends StatefulWidget {
  const ReadAloudVoiceSettings({super.key});

  @override
  State<ReadAloudVoiceSettings> createState() => _ReadAloudVoiceSettingsState();
}

class _ReadAloudVoiceSettingsState extends State<ReadAloudVoiceSettings> {
  List<ReadAloudVoice>? _voices;
  bool _failed = false;
  bool _loading = false;

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final voices = await ReadAloudService().voices();
      if (mounted) {
        setState(() {
          _voices = voices;
          _failed = false;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (kIsWeb) {
      return ListTile(
        title: Text(l10n.readAloudVoicesTitle),
        subtitle: Text(l10n.readAloudWebUnavailable),
      );
    }
    return ExpansionTile(
      key: const ValueKey('read_aloud_voice_settings'),
      title: Text(l10n.readAloudVoicesTitle),
      onExpansionChanged: (expanded) {
        if (expanded && _voices == null && !_failed) _load();
      },
      children: [_voiceChoices(context)],
    );
  }

  Widget _voiceChoices(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final voices = _voices;
    if (_failed) {
      return ListTile(
        title: Text(l10n.readAloudVoicesUnavailable),
        trailing: IconButton(
          onPressed: () {
            setState(() => _failed = false);
            _load();
          },
          icon: const Icon(Icons.refresh),
        ),
      );
    }
    if (voices == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      children: [
        ListTile(
          title: Text(l10n.readAloudLanguageMode),
          trailing: DropdownButton<String>(
            value: settings.readAloudLanguageMode,
            items: [
              DropdownMenuItem(
                value: 'auto',
                child: Text(l10n.readAloudAutomatic),
              ),
              DropdownMenuItem(value: 'en', child: Text(l10n.readAloudEnglish)),
              DropdownMenuItem(value: 'es', child: Text(l10n.readAloudSpanish)),
            ],
            onChanged: (mode) {
              if (mode != null) {
                unawaited(settings.setReadAloudLanguageMode(mode));
              }
            },
          ),
        ),
        _voiceRow(
          context,
          l10n.readAloudEnglishVoice,
          'en',
          settings.readAloudVoiceEn,
          settings.setReadAloudVoiceEn,
          voices,
        ),
        _voiceRow(
          context,
          l10n.readAloudSpanishVoice,
          'es',
          settings.readAloudVoiceEs,
          settings.setReadAloudVoiceEs,
          voices,
        ),
      ],
    );
  }

  Widget _voiceRow(
    BuildContext context,
    String title,
    String language,
    String selected,
    Future<void> Function(String) onChanged,
    List<ReadAloudVoice> voices,
  ) {
    final options = voices.where((v) => v.language == language).toList();
    final value = options.any((v) => v.id == selected) ? selected : null;
    final listening = context.watch<ReadAloudController>();
    final previewPlaying =
        listening.activePreviewVoiceId == value &&
        listening.active &&
        listening.state != ListeningState.completed &&
        listening.state != ListeningState.failed;
    return ListTile(
      title: Text(title),
      subtitle: options.isEmpty
          ? Text(AppLocalizations.of(context)!.readAloudVoicesUnavailable)
          : DropdownButton<String>(
              value: value,
              hint: Text(
                AppLocalizations.of(context)!.readAloudVoicesUnavailable,
              ),
              isExpanded: true,
              items: [
                for (final voice in options)
                  DropdownMenuItem(value: voice.id, child: Text(voice.name)),
              ],
              onChanged: (id) {
                if (id != null) unawaited(onChanged(id));
              },
            ),
      trailing: IconButton(
        tooltip: previewPlaying
            ? AppLocalizations.of(context)!.readAloudStopTooltip
            : AppLocalizations.of(context)!.readAloudPreview,
        onPressed: value == null
            ? null
            : previewPlaying
            ? () => unawaited(listening.stop())
            : () => unawaited(listening.previewVoice(value)),
        icon: Icon(
          previewPlaying
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline,
        ),
      ),
    );
  }
}
