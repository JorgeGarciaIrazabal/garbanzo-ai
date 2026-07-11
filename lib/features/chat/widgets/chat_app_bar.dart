import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/auth_state.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_drawer.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_search_sheet.dart';
import 'package:garbanzo_ai/features/chat/widgets/model_selector_widget.dart';
import 'package:garbanzo_ai/features/notifications/widgets/notification_bell.dart';

/// App bar for the chat page: conversation title, model selector (wide
/// layouts), notification bell, settings drawer trigger, and account menu.
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
    final modelProvider = context.watch<ModelProvider>();
    final showSidebar = context.isWide;

    return AppBar(
      title: Text(
        chatProvider.currentConversation?.displayTitle ?? 'New Chat',
        overflow: TextOverflow.ellipsis,
      ),
      leading: showSidebar
          ? null
          : IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => showMobileConversationDrawer(
                context: context,
                conversations: chatProvider.conversations,
                selectedId: chatProvider.currentConversation?.id,
                onSelect: (id) => chatProvider.loadConversation(id),
                onDelete: onDeleteConversation,
                onNewChat: () => chatProvider.clearCurrentConversation(),
                onTogglePin: (id) => chatProvider.togglePin(id),
              ),
            ),
      actions: [
        if (!showSidebar)
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search conversations',
            onPressed: () => showMobileSearchSheet(context),
          ),
        if (showSidebar)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ModelSelectorWidget(
              models: modelProvider.availableModels,
              selectedId: modelProvider.selectedModelId,
              onSelect: (id) {
                modelProvider.selectModel(id);
                if (chatProvider.currentConversation != null) {
                  chatProvider.updateConversation(model: id);
                }
              },
              isEnabled: !chatProvider.isSending,
            ),
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
                        chatProvider.panel.appTitle ?? 'Micro-app',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    tooltip: 'Reopen the micro-app panel',
                    onPressed: chatProvider.panel.reopen,
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.space_dashboard_outlined),
                  tooltip:
                      'Reopen ${chatProvider.panel.appTitle ?? 'micro-app'}',
                  onPressed: chatProvider.panel.reopen,
                ),
        const NotificationBell(),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: onOpenSettings,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.account_circle),
          tooltip: 'Account menu',
          onSelected: (value) async {
            if (value == 'logout') {
              await context.read<AuthState>().logout();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Sign out'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
