import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/read_aloud_voice_settings.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Shared Voice & Talk Mode settings tiles: Read Aloud voice, Talk Mode TTS
/// voice/speed/auto-play, STT auto-send, barge-in sensitivity, automatic
/// language switching, and preferred languages.
class VoiceSettingsTiles extends StatefulWidget {
  const VoiceSettingsTiles({
    super.key,
    this.loadVoices,
    this.dense = false,
    this.showDividers = true,
  });

  /// Voice catalog source; defaults to [AudioService.instance.listVoices].
  final Future<List<VoiceOption>> Function()? loadVoices;
  final bool dense;
  final bool showDividers;

  /// Unique languages in the voice catalog, in catalog order — the choices
  /// for the preferred-languages picker.
  @visibleForTesting
  static List<({String code, String name})> uniqueLanguages(
    List<VoiceOption> voices,
  ) {
    final seen = <String>{};
    return [
      for (final v in voices)
        if (seen.add(v.langCode)) (code: v.langCode, name: v.language),
    ];
  }

  @override
  State<VoiceSettingsTiles> createState() => _VoiceSettingsTilesState();
}

class _VoiceSettingsTilesState extends State<VoiceSettingsTiles> {
  List<VoiceOption> _voices = const [];
  bool _loadingVoices = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    setState(() {
      _loadingVoices = true;
      _loadError = null;
    });
    try {
      final voiceData =
          await (widget.loadVoices ?? AudioService.instance.listVoices)();
      if (!mounted) return;
      setState(() {
        _voices = voiceData;
        _loadingVoices = false;
      });
    } catch (e) {
      logDebug('Failed to load TTS voices: $e');
      if (!mounted) return;
      setState(() {
        _loadingVoices = false;
        _loadError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final itemStyle = widget.dense
        ? theme.textTheme.bodySmall
        : theme.textTheme.bodyMedium;

    Widget divider() => widget.showDividers
        ? const Divider(height: 1)
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ReadAloudVoiceSettings(),
        divider(),
        ListTile(
          title: Text(l10n.talkModeVoice),
          subtitle: _loadError != null
              ? Text(
                  l10n.failedToLoadVoices,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              : null,
          dense: widget.dense,
          trailing: _loadingVoices
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _loadError != null
              ? TextButton.icon(
                  key: const ValueKey('retry_load_voices'),
                  onPressed: _loadVoices,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l10n.labelRetry),
                )
              : DropdownButton<String>(
                  value: _voices.any((v) => v.id == settings.ttsVoice)
                      ? settings.ttsVoice
                      : (_voices.isNotEmpty ? _voices.first.id : null),
                  underline: const SizedBox.shrink(),
                  isDense: widget.dense,
                  items: _voices
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(
                            '${v.name} (${v.language})',
                            style: itemStyle,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) settings.setTtsVoice(value);
                  },
                ),
        ),
        divider(),
        ListTile(
          title: Text(l10n.titleSpeed),
          subtitle: Slider(
            value: settings.ttsSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            label: '${settings.ttsSpeed.toStringAsFixed(1)}x',
            onChanged: settings.setTtsSpeed,
          ),
          trailing: Text(
            '${settings.ttsSpeed.toStringAsFixed(1)}x',
            style: widget.dense ? theme.textTheme.bodySmall : null,
          ),
          dense: widget.dense,
        ),
        divider(),
        SwitchListTile(
          title: Text(l10n.titleAutoPlayResponses),
          subtitle: Text(l10n.titleReadAloudNewAssistantMessages),
          value: settings.autoPlayTts,
          onChanged: settings.setAutoPlayTts,
          dense: widget.dense,
        ),
        divider(),
        SwitchListTile(
          title: Text(l10n.titleAutoSendAfterTranscription),
          subtitle: Text(l10n.titleAutomaticallySendWhenVoiceInputFinishes),
          value: settings.autoSubmitStt,
          onChanged: settings.setAutoSubmitStt,
          dense: widget.dense,
        ),
        divider(),
        ListTile(
          title: Text(l10n.titleVoiceInterruption),
          subtitle: Text(l10n.titleTalkOverTheAiToInterrupt),
          dense: widget.dense,
          trailing: DropdownButton<BargeInSensitivity>(
            key: const ValueKey('barge_in_sensitivity'),
            value: settings.bargeInSensitivity,
            underline: const SizedBox.shrink(),
            isDense: widget.dense,
            items: [
              for (final level in BargeInSensitivity.values)
                DropdownMenuItem(
                  value: level,
                  child: Text(switch (level) {
                    BargeInSensitivity.off => l10n.bargeInOff,
                    BargeInSensitivity.low => l10n.bargeInLow,
                    BargeInSensitivity.normal => l10n.bargeInNormal,
                    BargeInSensitivity.high => l10n.bargeInHigh,
                  }, style: itemStyle),
                ),
            ],
            onChanged: (value) {
              if (value != null) settings.setBargeInSensitivity(value);
            },
          ),
        ),
        divider(),
        SwitchListTile(
          key: const ValueKey('auto_language_switch'),
          title: Text(l10n.titleAutomaticLanguageSwitching),
          subtitle: Text(l10n.titleReplyInTheLanguageYouSpeak),
          value: settings.autoLanguage,
          onChanged: settings.setAutoLanguage,
          dense: widget.dense,
        ),
        if (settings.autoLanguage && !_loadingVoices && _voices.isNotEmpty) ...[
          divider(),
          ListTile(
            title: Text(l10n.titleMyLanguages),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.onlySwitchBetweenTheseNoneMeans),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final lang in VoiceSettingsTiles.uniqueLanguages(
                      _voices,
                    ))
                      FilterChip(
                        key: ValueKey('language_chip_${lang.code}'),
                        label: Text(lang.name),
                        visualDensity: VisualDensity.compact,
                        selected: settings.preferredLanguages.contains(
                          lang.code,
                        ),
                        onSelected: (selected) {
                          final updated = List<String>.from(
                            settings.preferredLanguages,
                          );
                          selected
                              ? updated.add(lang.code)
                              : updated.remove(lang.code);
                          settings.setPreferredLanguages(updated);
                        },
                      ),
                  ],
                ),
              ],
            ),
            dense: widget.dense,
          ),
        ],
      ],
    );
  }
}
