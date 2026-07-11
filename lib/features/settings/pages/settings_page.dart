import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_editor_dialog.dart';
import 'package:garbanzo_ai/features/notifications/providers/notification_provider.dart';
import 'package:garbanzo_ai/features/usage/pages/usage_page.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/profile_section.dart';

/// Dedicated settings screen. Navigation target for `/settings`.
///
/// Sections: Profile, Appearance, Models, Voice, Memory, Notifications.
/// Each section is an anchor-tile in the sidebar on wide screens.
///
/// Created with its own ModelProvider, SystemPromptProvider, and
/// NotificationProvider because pushed routes don't inherit the chat page's
/// provider scope. SettingsProvider is app-level, so it's pulled from above.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ModelProvider()),
        ChangeNotifierProvider(create: (_) => SystemPromptProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: _SettingsPageContent(onLogout: onLogout),
    );
  }
}

class _SettingsPageContent extends StatefulWidget {
  const _SettingsPageContent({required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<_SettingsPageContent> createState() => _SettingsPageState();
}

enum _Section { profile, appearance, models, voice, memory, notifications }

class _SettingsPageState extends State<_SettingsPageContent> {
  _Section _selected = _Section.profile;
  UserInfo? _user;
  List<VoiceOption> _voices = const [];
  bool _loadingVoices = true;

  @override
  void initState() {
    super.initState();
    _user = AuthService.instance.cachedUser;
    _loadVoices();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final np = context.read<NotificationProvider>();
      if (np.preferences == null && !np.loadingPreferences) {
        np.loadPreferences();
      }
    });
  }

  Future<void> _refreshUser() async {
    final u = await AuthService.instance.getCurrentUser();
    if (!mounted) return;
    setState(() => _user = u ?? _user);
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await AudioService.instance.listVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loadingVoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingVoices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: wide ? _buildWide(theme) : _buildNarrow(theme),
    );
  }

  Widget _buildWide(ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 240,
          child: Material(
            color: theme.colorScheme.surfaceContainerLowest,
            child: ListView(
              children: _Section.values
                  .map(
                    (s) => ListTile(
                      leading: Icon(_iconFor(s)),
                      title: Text(_labelFor(s)),
                      selected: _selected == s,
                      onTap: () => setState(() => _selected = s),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: _buildSection(_selected),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _Section.values.map((s) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(icon: _iconFor(s), title: _labelFor(s)),
              const SizedBox(height: 12),
              _buildSection(s),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSection(_Section section) {
    switch (section) {
      case _Section.profile:
        return ProfileSection(
          user: _user,
          onUserChanged: _refreshUser,
          onLogout: widget.onLogout,
        );
      case _Section.appearance:
        return _appearanceSection();
      case _Section.models:
        return _modelsSection();
      case _Section.voice:
        return _voiceSection();
      case _Section.memory:
        return _memorySection();
      case _Section.notifications:
        return _notificationsSection();
    }
  }

  Widget _appearanceSection() {
    final settings = context.watch<SettingsProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('Show message metadata'),
              subtitle: const Text('Display token counts and response time'),
              value: settings.showMessageMetadata,
              onChanged: settings.setShowMessageMetadata,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Show system prompt in thread'),
              subtitle: const Text(
                'Display the active system prompt above the conversation',
              ),
              value: settings.showSystemPrompt,
              onChanged: settings.setShowSystemPrompt,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelsSection() {
    final modelProvider = context.watch<ModelProvider>();
    final promptProvider = context.watch<SystemPromptProvider>();
    final models = modelProvider.availableModels;
    final defaultModel = _user?.defaultModel;
    final userDefaultPrompt = promptProvider.userDefault;
    final theme = Theme.of(context);

    String truncate(String s) =>
        s.length <= 120 ? s : '${s.substring(0, 120)}…';

    Future<void> editDefaultPrompt() async {
      final result = await SystemPromptEditorDialog.show(
        context,
        initialContent: userDefaultPrompt,
        title: 'Global default system prompt',
        subtitle:
            'Applied to every new conversation unless overridden per-chat.',
      );
      if (result == null || result.isCancelled) return;
      if (result.isClear) {
        await promptProvider.setUserDefault(null);
      } else {
        await promptProvider.setUserDefault(result.content);
      }
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Default model'),
            subtitle: Text(
              defaultModel == null || defaultModel.isEmpty
                  ? 'Server fallback (usually llama3.2)'
                  : defaultModel,
              style: theme.textTheme.bodySmall,
            ),
            trailing: models.isEmpty
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : DropdownButton<String?>(
                    value: models.any((m) => m.id == defaultModel)
                        ? defaultModel
                        : null,
                    underline: const SizedBox.shrink(),
                    hint: const Text('Auto'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Auto'),
                      ),
                      ...models.map(
                        (m) => DropdownMenuItem<String?>(
                          value: m.id,
                          child: Text(m.name),
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      final ok = await modelProvider.setDefaultModel(value);
                      if (ok && mounted) {
                        if (value != null) modelProvider.selectModel(value);
                        await _refreshUser();
                      }
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Global default system prompt'),
            subtitle: Text(
              (userDefaultPrompt == null || userDefaultPrompt.isEmpty)
                  ? 'Not set — using built-in defaults'
                  : truncate(userDefaultPrompt),
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: editDefaultPrompt,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Token usage'),
            subtitle: const Text('Charts by model, conversation, day'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const UsagePage()));
            },
          ),
        ],
      ),
    );
  }

  Widget _voiceSection() {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Voice'),
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
                    items: _voices
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(
                              '${v.name} (${v.language})',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) settings.setTtsVoice(value);
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Speed'),
            subtitle: Slider(
              value: settings.ttsSpeed,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              label: '${settings.ttsSpeed.toStringAsFixed(1)}x',
              onChanged: settings.setTtsSpeed,
            ),
            trailing: Text('${settings.ttsSpeed.toStringAsFixed(1)}x'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Auto-play responses'),
            subtitle: const Text('Read aloud new assistant messages'),
            value: settings.autoPlayTts,
            onChanged: settings.setAutoPlayTts,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Auto-send after transcription'),
            subtitle: const Text(
              'Automatically send when voice input finishes',
            ),
            value: settings.autoSubmitStt,
            onChanged: settings.setAutoSubmitStt,
          ),
        ],
      ),
    );
  }

  Widget _memorySection() {
    return Card(
      child: Column(
        children: const [
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Saved memories'),
            subtitle: Text(
              'Memories are managed from the chat screen via the memory page. '
              'Open the chat to review, edit, or delete them.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationsSection() {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        final prefs = provider.preferences;
        if (prefs == null) {
          if (!provider.loadingPreferences) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.loadPreferences();
            });
          }
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Chat responses'),
                subtitle: const Text(
                  'Notify when assistant replies while app is in background',
                ),
                value: prefs.chatResponsesEnabled,
                onChanged: (v) =>
                    provider.updatePreferences(chatResponsesEnabled: v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Reminders'),
                subtitle: const Text('Scheduled reminders and check-ins'),
                value: prefs.remindersEnabled,
                onChanged: (v) =>
                    provider.updatePreferences(remindersEnabled: v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('System alerts'),
                subtitle: const Text('Account and system notifications'),
                value: prefs.systemAlertsEnabled,
                onChanged: (v) =>
                    provider.updatePreferences(systemAlertsEnabled: v),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconFor(_Section s) {
    switch (s) {
      case _Section.profile:
        return Icons.person_outline;
      case _Section.appearance:
        return Icons.palette_outlined;
      case _Section.models:
        return Icons.smart_toy_outlined;
      case _Section.voice:
        return Icons.record_voice_over_outlined;
      case _Section.memory:
        return Icons.bookmark_outline;
      case _Section.notifications:
        return Icons.notifications_outlined;
    }
  }

  String _labelFor(_Section s) {
    switch (s) {
      case _Section.profile:
        return 'Profile';
      case _Section.appearance:
        return 'Appearance';
      case _Section.models:
        return 'Models';
      case _Section.voice:
        return 'Voice';
      case _Section.memory:
        return 'Memory';
      case _Section.notifications:
        return 'Notifications';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
