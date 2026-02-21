import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_service.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import 'chat_input_widget.dart';
import 'chat_message_widget.dart';
import 'conversation_list_widget.dart';
import 'empty_chat_state.dart';
import 'mobile_drawer.dart';
import 'model_selector_widget.dart';

/// Main chat page with conversation sidebar and message area.
///
/// Provides both [ChatProvider] (conversations/messages) and [ModelProvider]
/// (model selection) via the widget tree.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ModelProvider(),
      child: Builder(
        builder: (context) {
          final modelProvider = context.read<ModelProvider>();
          return ChangeNotifierProvider(
            create: (_) => ChatProvider(
              selectedModelId: () => modelProvider.selectedModelId,
            ),
            child: _ChatPageContent(onLogout: onLogout),
          );
        },
      ),
    );
  }
}

class _ChatPageContent extends StatefulWidget {
  const _ChatPageContent({required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<_ChatPageContent> createState() => _ChatPageContentState();
}

class _ChatPageContentState extends State<_ChatPageContent> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _showSidebar(BuildContext context) =>
      MediaQuery.of(context).size.width > 800;

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      body: Row(
        children: [
          if (_showSidebar(context))
            ConversationListWidget(
              conversations: chatProvider.conversations,
              selectedId: chatProvider.currentConversation?.id,
              onSelect: (id) => chatProvider.loadConversation(id),
              onDelete: (id) => chatProvider.deleteConversation(id),
              onNewChat: () => chatProvider.clearCurrentConversation(),
              isLoading: chatProvider.isLoadingConversations,
            ),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(chatProvider, modelProvider, colorScheme),
                if (chatProvider.error != null)
                  _ErrorBanner(
                    message: chatProvider.error!,
                    onDismiss: chatProvider.clearError,
                  ),
                Expanded(child: _buildMessageList(chatProvider, theme)),
                ChatInputWidget(
                  onSend: (message) => chatProvider.sendMessage(message),
                  onStop: () => chatProvider.stopStreaming(),
                  isLoading: chatProvider.isSending,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    ChatProvider chatProvider,
    ModelProvider modelProvider,
    ColorScheme colorScheme,
  ) {
    return AppBar(
      title: Text(
        chatProvider.currentConversation?.displayTitle ?? 'New Chat',
        overflow: TextOverflow.ellipsis,
      ),
      leading: _showSidebar(context)
          ? null
          : IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => showMobileConversationDrawer(
                context: context,
                conversations: chatProvider.conversations,
                selectedId: chatProvider.currentConversation?.id,
                onSelect: (id) => chatProvider.loadConversation(id),
                onDelete: (id) => chatProvider.deleteConversation(id),
                onNewChat: () => chatProvider.clearCurrentConversation(),
              ),
            ),
      actions: [
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
        PopupMenuButton<String>(
          icon: const Icon(Icons.account_circle),
          onSelected: (value) async {
            if (value == 'logout') {
              await AuthService.instance.logout();
              widget.onLogout();
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

  Widget _buildMessageList(ChatProvider chatProvider, ThemeData theme) {
    if (chatProvider.messages.isEmpty &&
        chatProvider.currentConversation == null) {
      return EmptyChatState(
        onSendMessage: (msg) => chatProvider.sendMessage(msg),
      );
    }

    if (chatProvider.messages.isEmpty && chatProvider.isLoadingConversations) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: chatProvider.messages.length,
      itemBuilder: (context, index) {
        final message = chatProvider.messages[index];
        final isLastMessage = index == chatProvider.messages.length - 1;

        return ChatMessageWidget(
          message: message,
          isStreaming:
              isLastMessage && chatProvider.isSending && message.isAssistant,
        );
      },
    );
  }
}

/// Dismissible error banner displayed at the top of the chat area.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close,
                color: colorScheme.onErrorContainer, size: 20),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
