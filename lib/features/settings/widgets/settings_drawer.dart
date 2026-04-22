import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_service.dart';
import '../../admin/pages/admin_page.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/providers/model_provider.dart';
import '../../chat/providers/system_prompt_provider.dart';
import '../../chat/services/audio_service.dart';
import '../../chat/widgets/system_prompt_editor_dialog.dart';
import '../../memory/pages/memory_page.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../scheduled_actions/pages/scheduled_actions_page.dart';
import '../../tools/pages/skills_library_page.dart';
import '../../tools/providers/tool_provider.dart';
import '../../usage/pages/usage_page.dart';
import '../pages/settings_page.dart';
import '../providers/settings_provider.dart';

/// Right-side drawer with extensible settings sections.
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key, this.onLogout});

  /// Forwarded to the dedicated settings page so its Profile section can
  /// sign out. Optional: callers that don't pass it get an in-place logout
  /// via [AuthService] but no navigation callback.
  final VoidCallback? onLogout;

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
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open full settings'),
              subtitle: const Text('Profile, appearance, models, and more'),
              dense: true,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      onLogout: widget.onLogout ?? () {},
                    ),
                  ),
                );
              },
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
                  // -- System prompt section --
                  _buildSystemPromptSection(context, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Tools / Skills section --
                  _buildToolsSection(context, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Navigation section (Skills library, Admin) --
                  _buildNavigationSection(context, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Memory section --
                  _buildMemorySection(context, settings, colorScheme, theme),
                  const Divider(height: 24),
                  // -- Notifications section --
                  _buildNotificationsSection(context, colorScheme, theme),
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

  Widget _buildSystemPromptSection(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final chatProvider = context.watch<ChatProvider>();
    final promptProvider = context.watch<SystemPromptProvider>();
    final conversation = chatProvider.currentConversation;
    final convPrompt = conversation?.systemPrompt;
    final userDefault = promptProvider.userDefault;

    final effectivePrompt = (convPrompt?.isNotEmpty ?? false)
        ? convPrompt!
        : (userDefault ?? '');
    final effectiveSource = (convPrompt?.isNotEmpty ?? false)
        ? 'Conversation'
        : (userDefault != null && userDefault.isNotEmpty
            ? 'Global default'
            : 'None');

    Future<void> editConversationPrompt() async {
      if (conversation == null) return;
      final result = await SystemPromptEditorDialog.show(
        context,
        initialContent: convPrompt,
        title: 'Conversation system prompt',
        subtitle:
            'Overrides your global default for this conversation only.',
      );
      if (result == null || result.isCancelled) return;
      if (result.isClear) {
        await chatProvider.updateConversation(clearSystemPrompt: true);
      } else {
        await chatProvider.updateConversation(systemPrompt: result.content);
      }
    }

    Future<void> editUserDefault() async {
      final result = await SystemPromptEditorDialog.show(
        context,
        initialContent: userDefault,
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

    String truncate(String s) =>
        s.length <= 80 ? s : '${s.substring(0, 80)}…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.assignment_outlined,
          title: 'System Prompt',
        ),
        // Per-conversation
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: const Text('This conversation'),
          subtitle: conversation == null
              ? const Text('Start a conversation to set a prompt')
              : Text(
                  convPrompt == null || convPrompt.isEmpty
                      ? 'Using: $effectiveSource'
                      : truncate(convPrompt),
                  style: theme.textTheme.bodySmall,
                ),
          trailing: conversation == null
              ? null
              : Icon(Icons.edit, size: 18, color: colorScheme.primary),
          enabled: conversation != null,
          dense: true,
          onTap: conversation == null ? null : editConversationPrompt,
        ),
        // Global default
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Global default'),
          subtitle: Text(
            (userDefault == null || userDefault.isEmpty)
                ? 'Not set — using built-in defaults'
                : truncate(userDefault),
            style: theme.textTheme.bodySmall,
          ),
          trailing: Icon(Icons.edit, size: 18, color: colorScheme.primary),
          dense: true,
          onTap: editUserDefault,
        ),
        if (effectivePrompt.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'No system prompt active.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
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

  /// Renders navigation entries: Skills library (always), Admin (admin only).
  Widget _buildNavigationSection(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isAdmin = AuthService.instance.cachedUser?.isAdmin ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.widgets_outlined,
          title: 'More',
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Skills library'),
          subtitle: const Text('Browse available MCP tools'),
          dense: true,
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SkillsLibraryPage()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Scheduled actions'),
          subtitle: const Text('Reminders and recurring prompts'),
          dense: true,
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScheduledActionsPage()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('Token usage'),
          subtitle: const Text('Charts by model, conversation, day'),
          dense: true,
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UsagePage()),
            );
          },
        ),
        if (isAdmin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Admin'),
            subtitle: const Text('Manage users and MCP servers'),
            dense: true,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminPage()),
              );
            },
          ),
      ],
    );
  }

  /// Renders the per-conversation tool-selection UI. Shows nothing until a
  /// conversation is active. Semantics:
  ///  - `enabled_tools == null` means "inherit all tools" (the default).
  ///  - An explicit list means "only these tools are enabled".
  ///  - An empty list means "no tools enabled".
  Widget _buildToolsSection(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.currentConversation;

    if (conversation == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _SectionHeader(icon: Icons.build_outlined, title: 'Tools'),
          ListTile(
            title: Text('Tools'),
            subtitle: Text('Start a conversation to pick tools'),
            enabled: false,
            dense: true,
          ),
        ],
      );
    }

    return Consumer<ToolProvider>(
      builder: (context, toolProvider, _) {
        // Lazy-load tool catalog the first time this section renders.
        if (!toolProvider.isLoaded && !toolProvider.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            toolProvider.load();
          });
        }

        final enabled = conversation.enabledTools;
        final allInherited = enabled == null;
        final tools = toolProvider.tools;
        final allKeys = tools.map((t) => t.qualifiedKey).toSet();

        Set<String> effectiveSelection() {
          if (allInherited) return allKeys;
          return enabled.toSet();
        }

        final selected = effectiveSelection();

        Future<void> applySelection(Set<String> next) async {
          // When selection covers every known tool, prefer null (inherit all)
          // so future additions are automatically enabled.
          if (next.length == allKeys.length &&
              next.containsAll(allKeys) &&
              allKeys.isNotEmpty) {
            await chatProvider.updateConversation(clearEnabledTools: true);
            return;
          }
          await chatProvider.updateConversation(enabledTools: next.toList());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.build_outlined,
              title: 'Tools',
            ),
            if (toolProvider.isLoading && tools.isEmpty)
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
                    Text('Loading tools…'),
                  ],
                ),
              )
            else if (toolProvider.error != null && tools.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  toolProvider.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              )
            else if (tools.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No MCP tools available. Configure a server from the '
                  'Admin panel.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              SwitchListTile(
                title: const Text('All tools'),
                subtitle: Text(
                  allInherited
                      ? 'Every available tool is enabled'
                      : '${selected.length} of ${allKeys.length} tools enabled',
                  style: theme.textTheme.bodySmall,
                ),
                value: allInherited,
                onChanged: (value) {
                  if (value) {
                    chatProvider.updateConversation(clearEnabledTools: true);
                  } else {
                    // Switch off "all": materialize current set so further
                    // unchecks will remove specific tools.
                    chatProvider.updateConversation(
                      enabledTools: allKeys.toList(),
                    );
                  }
                },
                dense: true,
              ),
              ...toolProvider.toolsByServer.entries.map((entry) {
                final serverName = entry.key;
                final serverTools = entry.value;
                final serverEnabledCount = serverTools
                    .where((t) => selected.contains(t.qualifiedKey))
                    .length;
                return ExpansionTile(
                  leading: const Icon(Icons.extension, size: 18),
                  title: Text(serverName),
                  subtitle: Text(
                    '$serverEnabledCount of ${serverTools.length} enabled',
                    style: theme.textTheme.bodySmall,
                  ),
                  childrenPadding:
                      const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                  children: serverTools.map((tool) {
                    final key = tool.qualifiedKey;
                    final isOn = selected.contains(key);
                    return CheckboxListTile(
                      value: isOn,
                      onChanged: (v) {
                        final next = Set<String>.from(selected);
                        if (v == true) {
                          next.add(key);
                        } else {
                          next.remove(key);
                        }
                        applySelection(next);
                      },
                      title: Text(
                        tool.name,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      subtitle: tool.description == null ||
                              tool.description!.isEmpty
                          ? null
                          : Text(
                              tool.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }).toList(),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  /// Per-user notification channel toggles. Lazy-loads preferences on first
  /// render and applies changes optimistically.
  Widget _buildNotificationsSection(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
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
            const _SectionHeader(
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
