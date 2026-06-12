import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../chat/services/audio_service.dart';
import '../../../notifications/providers/notification_provider.dart';
import '../../providers/settings_provider.dart';
import 'section_header.dart';

/// App-wide preferences: appearance, chat display, voice, notifications.
class AppSettingsSection extends StatelessWidget {
  const AppSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _AppearanceTiles(),
        Divider(height: 24),
        _ChatTiles(),
        Divider(height: 24),
        VoiceSettingsTiles(),
        Divider(height: 24),
        _NotificationTiles(),
      ],
    );
  }
}

class _AppearanceTiles extends StatelessWidget {
  const _AppearanceTiles();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(icon: Icons.palette_outlined, title: 'Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (Set<AppThemeMode> selection) {
              settings.setThemeMode(selection.first);
            },
          ),
        ),
      ],
    );
  }
}

class _ChatTiles extends StatelessWidget {
  const _ChatTiles();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(icon: Icons.chat_bubble_outline, title: 'Chat'),
        SwitchListTile(
          title: const Text('Show message metadata'),
          subtitle: const Text('Display token counts and response time'),
          value: settings.showMessageMetadata,
          onChanged: (value) => settings.setShowMessageMetadata(value),
          dense: true,
        ),
        SwitchListTile(
          title: const Text('Show system prompt in thread'),
          subtitle: const Text(
            'Display the active system prompt above the conversation',
          ),
          value: settings.showSystemPrompt,
          onChanged: (value) => settings.setShowSystemPrompt(value),
          dense: true,
        ),
      ],
    );
  }
}

/// TTS voice/speed/auto-play plus the STT auto-send toggle. Stateful because
/// the voice list is fetched from the backend once per drawer open.
class VoiceSettingsTiles extends StatefulWidget {
  const VoiceSettingsTiles({super.key});

  @override
  State<VoiceSettingsTiles> createState() => _VoiceSettingsTilesState();
}

class _VoiceSettingsTilesState extends State<VoiceSettingsTiles> {
  List<VoiceOption> _voices = [];
  bool _loadingVoices = true;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final voiceData = await AudioService.instance.listVoices();
      if (mounted) {
        setState(() {
          _voices = voiceData;
          _loadingVoices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingVoices = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.record_voice_over,
          title: 'Voice',
        ),
        // Voice selector
        ListTile(
          title: const Text('Voice'),
          dense: true,
          trailing: _loadingVoices
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : DropdownButton<String>(
                  value: _voices.any((v) => v.id == settings.ttsVoice)
                      ? settings.ttsVoice
                      : (_voices.isNotEmpty ? _voices.first.id : null),
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: _voices
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(
                            '${v.name} (${v.language})',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) settings.setTtsVoice(value);
                  },
                ),
        ),
        // Speed slider
        ListTile(
          title: const Text('Speed'),
          subtitle: Slider(
            value: settings.ttsSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            label: '${settings.ttsSpeed.toStringAsFixed(1)}x',
            onChanged: (value) => settings.setTtsSpeed(value),
          ),
          trailing: Text(
            '${settings.ttsSpeed.toStringAsFixed(1)}x',
            style: theme.textTheme.bodySmall,
          ),
          dense: true,
        ),
        // Auto-play toggle
        SwitchListTile(
          title: const Text('Auto-play responses'),
          subtitle: const Text('Read aloud new assistant messages'),
          value: settings.autoPlayTts,
          onChanged: (value) => settings.setAutoPlayTts(value),
          dense: true,
        ),
        SwitchListTile(
          title: const Text('Auto-send after transcription'),
          subtitle: const Text('Automatically send when voice input finishes'),
          value: settings.autoSubmitStt,
          onChanged: (value) => settings.setAutoSubmitStt(value),
          dense: true,
        ),
      ],
    );
  }
}

/// Per-user notification channel toggles. Lazy-loads preferences on first
/// render and applies changes optimistically.
class _NotificationTiles extends StatelessWidget {
  const _NotificationTiles();

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        final prefs = provider.preferences;
        if (prefs == null && !provider.loadingPreferences) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.loadPreferences();
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
            ),
            if (prefs == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Loading preferences…'),
                  ],
                ),
              )
            else ...[
              SwitchListTile(
                title: const Text('Chat responses'),
                subtitle: const Text(
                  'Notify when assistant replies while app is in background',
                ),
                value: prefs.chatResponsesEnabled,
                onChanged: (value) => provider.updatePreferences(
                  chatResponsesEnabled: value,
                ),
                dense: true,
              ),
              SwitchListTile(
                title: const Text('Reminders'),
                subtitle: const Text('Scheduled reminders and check-ins'),
                value: prefs.remindersEnabled,
                onChanged: (value) => provider.updatePreferences(
                  remindersEnabled: value,
                ),
                dense: true,
              ),
              SwitchListTile(
                title: const Text('System alerts'),
                subtitle: const Text('Account and system notifications'),
                value: prefs.systemAlertsEnabled,
                onChanged: (value) => provider.updatePreferences(
                  systemAlertsEnabled: value,
                ),
                dense: true,
              ),
            ],
          ],
        );
      },
    );
  }
}
