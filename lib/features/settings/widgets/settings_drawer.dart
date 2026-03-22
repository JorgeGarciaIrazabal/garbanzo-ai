import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../chat/providers/chat_provider.dart';
import '../../chat/providers/model_provider.dart';
import '../../chat/services/audio_service.dart';
import '../../memory/pages/memory_page.dart';
import '../providers/settings_provider.dart';

/// Right-side drawer with extensible settings sections.
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
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
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();

    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.settings, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Settings', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // -- Appearance section --
                  _buildAppearanceSection(context, settings, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Chat section --
                  _buildChatSection(context, settings, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Model section --
                  _buildModelSection(context, settings, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Memory section --
                  _buildMemorySection(context, settings, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Voice / TTS section --
                  _buildVoiceSection(context, settings, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Speech Input / STT section --
                  _buildSttSection(context, settings, colorScheme, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    SettingsProvider settings,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(icon: Icons.palette_outlined, title: 'Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AppThemeMode>(
            segments: [
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.light,
                label: const Text('Light'),
                icon: const Icon(Icons.light_mode),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.dark,
                label: const Text('Dark'),
                icon: const Icon(Icons.dark_mode),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.system,
                label: const Text('System'),
                icon: const Icon(Icons.brightness_auto),
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

  Widget _buildMemorySection(
    BuildContext context,
    SettingsProvider settings,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.currentConversation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.bookmark_border, title: 'Memory'),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('View memories'),
          subtitle: const Text('Manage saved memories'),
          dense: true,
          onTap: () {
            Navigator.of(context).pop(); // Close drawer
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemoryPage()),
            );
          },
        ),
        if (conversation != null)
          SwitchListTile(
            title: const Text('Use memory'),
            subtitle: const Text('Inject saved memories into this conversation'),
            value: conversation.useMemory,
            onChanged: (value) {
              chatProvider.updateConversation(useMemory: value);
            },
            dense: true,
          )
        else
          const ListTile(
            title: Text('Use memory'),
            subtitle: Text('Start a conversation to toggle memory'),
            dense: true,
            enabled: false,
          ),
      ],
    );
  }

  Widget _buildModelSection(
    BuildContext context,
    SettingsProvider settings,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final modelProvider = context.watch<ModelProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final models = modelProvider.availableModels;
    final selectedId = modelProvider.selectedModelId;

    // Find selected model name
    String? selectedName;
    for (final model in models) {
      if (model.id == selectedId) {
        selectedName = model.name;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.smart_toy, title: 'Model'),
        ListTile(
          title: const Text('LLM Model'),
          subtitle: Text(
            selectedName ?? selectedId ?? 'No model selected',
            style: theme.textTheme.bodySmall,
          ),
          dense: true,
          trailing: DropdownButton<String>(
            value: models.any((m) => m.id == selectedId) ? selectedId : null,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: models
                .map((m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        m.name,
                        style: theme.textTheme.bodySmall,
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                modelProvider.selectModel(value);
                if (chatProvider.currentConversation != null) {
                  chatProvider.updateConversation(model: value);
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceSection(
    BuildContext context,
    SettingsProvider settings,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.record_voice_over, title: 'Text-to-Speech'),
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
      ],
    );
  }

  Widget _buildSttSection(
    BuildContext context,
    SettingsProvider settings,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.mic, title: 'Speech Input'),
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

  Widget _buildChatSection(
    BuildContext context,
    SettingsProvider settings,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.chat_bubble_outline, title: 'Chat'),
        SwitchListTile(
          title: const Text('Show message metadata'),
          subtitle: const Text('Display token counts and response time'),
          value: settings.showMessageMetadata,
          onChanged: (value) => settings.setShowMessageMetadata(value),
          dense: true,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
