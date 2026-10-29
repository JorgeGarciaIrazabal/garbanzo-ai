import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/section_header.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

export 'package:garbanzo_ai/features/settings/widgets/voice_settings_tiles.dart';

/// Quick 1-tap theme toggle kept in the right-hand drawer. All full app
/// preferences (language, models, MCP tools, voice & Talk Mode, memory,
/// notification channels, updates) live on `/settings` ([SettingsPage]).
class AppSettingsSection extends StatelessWidget {
  const AppSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.palette_outlined,
          title: l10n.titleAppearance,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AppThemeMode>(
            segments: [
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.light,
                label: Text(l10n.labelLight),
                icon: const Icon(Icons.light_mode),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.dark,
                label: Text(l10n.labelDark),
                icon: const Icon(Icons.dark_mode),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.system,
                label: Text(l10n.labelSystem),
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
}
