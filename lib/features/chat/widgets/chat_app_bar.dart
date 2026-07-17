import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_drawer.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_search_sheet.dart';
import 'package:garbanzo_ai/features/chat/widgets/style_picker.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// App bar for the chat page: conversation title, model selector, and
/// settings drawer trigger.
///
/// On narrow layouts the leading menu button opens the mobile conversation
/// drawer instead of the (hidden) sidebar.
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.onOpenSettings,
    required this.onDeleteConversation,
  });

  /// Opens the settings end-drawer (owned by the page's Scaffold).
  final VoidCallback onOpenSettings;

  /// Delete-with-undo flow owned by the page (needs its ScaffoldMessenger).
  final ValueChanged<String> onDeleteConversation;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final showSidebar = context.isWide;

    return AppBar(
      title: Text(
        chatProvider.currentConversation?.displayTitle ??
            AppLocalizations.of(context)!.labelNewChat,
        overflow: TextOverflow.ellipsis,
      ),
      leading: showSidebar
          ? null
          : IconButton(
              tooltip: AppLocalizations.of(context)!.tooltipOpenConversations,
              icon: const Icon(Icons.menu),
              onPressed: () => showMobileConversationDrawer(
                context: context,
                conversations: chatProvider.conversations,
                selectedId: chatProvider.currentConversation?.id,
                onSelect: (id) => chatProvider.loadConversation(id),
                onDelete: onDeleteConversation,
                onNewChat: () => chatProvider.clearCurrentConversation(),
                onTogglePin: (id) => chatProvider.togglePin(id),
                onMuteConversation: (id, duration) =>
                    chatProvider.setMute(id, duration),
              ),
            ),
      actions: [
        if (!showSidebar)
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: AppLocalizations.of(context)!.tooltipSearchConversations,
            onPressed: () => showMobileSearchSheet(context),
          ),
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: StylePickerButton(),
        ),
        // Closed micro-app panel: offer a way back in without re-running
        // the tool (on narrow screens closing it is otherwise a dead end).
        if (chatProvider.panel.canReopen)
          showSidebar
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ActionChip(
                    avatar: const Icon(
                      Icons.space_dashboard_outlined,
                      size: 16,
                    ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        chatProvider.panel.appTitle ??
                            AppLocalizations.of(context)!.labelMicroApp,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    tooltip: AppLocalizations.of(
                      context,
                    )!.tooltipReopenMicroAppPanel,
                    onPressed: chatProvider.panel.reopen,
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.space_dashboard_outlined),
                  tooltip: AppLocalizations.of(context)!.tooltipReopenApp(
                    chatProvider.panel.appTitle ??
                        AppLocalizations.of(context)!.labelMicroApp,
                  ),
                  onPressed: chatProvider.panel.reopen,
                ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: AppLocalizations.of(context)!.settings,
          onPressed: onOpenSettings,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
