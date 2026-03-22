import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_service.dart';
import '../../../core/responsive.dart';
import '../../memory/providers/memory_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/widgets/settings_drawer.dart';
import '../models/chat_attachment.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import 'chat_input_widget.dart';
import 'chat_message_widget.dart';
import 'context_summary_widget.dart';
import 'context_window_indicator.dart';
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
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => ChatProvider(
                  selectedModelId: () => modelProvider.selectedModelId,
                ),
              ),
              ChangeNotifierProvider(create: (_) => MemoryProvider()),
              ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ],
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  bool _isDragOver = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? _getLastTokensPrompt(ChatProvider chatProvider) {
    final msgs = chatProvider.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      final meta = msgs[i].metadata;
      if (meta != null) {
        final t = meta['tokens_prompt'];
        if (t != null) return (t as num).toInt();
      }
    }
    return null;
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

  bool _showSidebar(BuildContext context) => context.isWide;

  /// Handle dropped files and add them as attachments.
  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    setState(() => _isDragOver = false);

    final chatProvider = context.read<ChatProvider>();
    if (!chatProvider.hasActiveConversation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a conversation first')),
      );
      return;
    }

    final added = <ChatAttachment>[];
    final rejected = <String>[];
    final validationErrors = <String>[];

    for (final file in files) {
      if (file is! File) continue;

      final bytes = await file.readAsBytes();
      final mime = _inferMime(file.path, bytes);
      final filename = file.path.split('/').last;
      final isImage = mime.startsWith('image/');
      final isPdf = mime == 'application/pdf';
      final isSpreadsheet = mime.endsWith('spreadsheetml.sheet') ||
          mime == 'application/vnd.ms-excel' ||
          mime == 'application/vnd.oasis.opendocument.spreadsheet' ||
          filename.toLowerCase().endsWith('.csv') ||
          filename.toLowerCase().endsWith('.xlsx') ||
          filename.toLowerCase().endsWith('.xls') ||
          filename.toLowerCase().endsWith('.ods');

      final maxBytes = isImage
          ? 5 * 1024 * 1024 // 5 MB for images
          : isPdf
              ? 20 * 1024 * 1024 // 20 MB for PDFs
              : isSpreadsheet
                  ? 10 * 1024 * 1024 // 10 MB for spreadsheets/CSV
                  : 10 * 1024 * 1024; // 10 MB for other documents

      if (bytes.length > maxBytes) {
        rejected.add('$filename (${_formatFileSize(bytes.length)} - max ${_formatFileSize(maxBytes)})');
        continue;
      }

      // Check for duplicate filenames
      if (chatProvider.pendingAttachments?.any((a) => a.name == filename) == true) {
        validationErrors.add('Duplicate file: $filename');
        continue;
      }

      added.add(ChatAttachment.fromPicked(
        name: filename,
        mimeType: mime,
        bytes: bytes,
      ));
    }

    // Show validation errors
    if (validationErrors.isNotEmpty && mounted) {
      for (final error in validationErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }

    // Show rejection errors
    if (rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Files too large:\n${rejected.join('\n')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (added.isNotEmpty) {
      chatProvider.addAttachments(added);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _inferMime(String path, Uint8List bytes) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xml')) return 'application/xml';
    return 'text/plain';
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const SettingsDrawer(),
      body: DragTarget<List<dynamic>>(
      onWillAccept: (data) {
        if (data == null || data.isEmpty) return false;
        setState(() => _isDragOver = true);
        return true;
      },
      onLeave: (_) {
        setState(() => _isDragOver = false);
      },
      onAccept: _handleDroppedFiles,
      builder: (context, candidateData, rejectedData) {
        return Stack(
          children: [
            Row(
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
                      Builder(
                        builder: (ctx) {
                          final tokensUsed =
                              _getLastTokensPrompt(chatProvider);
                          final contextLength =
                              modelProvider.selectedModel?.contextLength;
                          if (tokensUsed != null &&
                              contextLength != null &&
                              contextLength > 0) {
                            return ContextWindowIndicator(
                              tokensUsed: tokensUsed,
                              contextLength: contextLength,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      Expanded(child: _buildMessageList(chatProvider, theme)),
                      Consumer<ChatProvider>(
                        builder: (context, provider, _) {
                          return ChatInputWidget(
                            onSend: (message, attachments) {
                              // Merge any pending attachments from drag-drop
                              final merged = [...attachments];
                              if (provider.pendingAttachments != null) {
                                merged.addAll(provider.pendingAttachments!);
                                provider.clearPendingAttachments();
                              }
                              provider.sendMessage(message, attachments: merged);
                            },
                            onStop: () => chatProvider.stopStreaming(),
                            isLoading: chatProvider.isSending,
                            initialAttachments: provider.pendingAttachments,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isDragOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      border: Border.all(
                        color: colorScheme.primary,
                        width: 4,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              size: 64,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Drop files to attach',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Images, PDFs, CSVs, and text files',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
        if (_showSidebar(context))
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
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            _scaffoldKey.currentState?.openEndDrawer();
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.account_circle),
          tooltip: 'Account menu',
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

    final summary = chatProvider.currentConversation?.contextSummary;
    final hasSummary = summary != null && summary.isNotEmpty;
    final itemOffset = hasSummary ? 1 : 0;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: chatProvider.messages.length + itemOffset,
      itemBuilder: (context, index) {
        if (hasSummary && index == 0) {
          return ContextSummaryWidget(summary: summary);
        }
        final msgIndex = index - itemOffset;
        final message = chatProvider.messages[msgIndex];
        final isLastMessage = msgIndex == chatProvider.messages.length - 1;

        return ChatMessageWidget(
          message: message,
          isStreaming:
              isLastMessage && chatProvider.isSending && message.isAssistant,
          conversationId: chatProvider.currentConversation?.id,
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
