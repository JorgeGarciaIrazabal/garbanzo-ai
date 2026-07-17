import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/section_header.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Per-conversation tool-selection UI. Shows nothing until a conversation is
/// active. Semantics:
///  - `enabled_tools == null` means "inherit all tools" (the default).
///  - An explicit list means "only these tools are enabled".
///  - An empty list means "no tools enabled".
class ToolsPicker extends StatelessWidget {
  const ToolsPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.currentConversation;

    if (conversation == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.build_outlined,
            title: AppLocalizations.of(context)!.labelTools,
          ),
          ListTile(
            title: Text(AppLocalizations.of(context)!.labelTools),
            subtitle: Text(
              AppLocalizations.of(context)!.titleStartAConversationToPickTools,
            ),
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
            SectionHeader(
              icon: Icons.build_outlined,
              title: AppLocalizations.of(context)!.labelTools,
            ),
            if (toolProvider.isLoading && tools.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.loadingTools),
                  ],
                ),
              )
            else if (toolProvider.error != null && tools.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  toolProvider.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              )
            else if (tools.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                title: Text(AppLocalizations.of(context)!.titleAllTools),
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
                  childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
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
                      subtitle:
                          tool.description == null || tool.description!.isEmpty
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
}
