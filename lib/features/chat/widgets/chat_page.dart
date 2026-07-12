import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/core/widgets/fade_slide_in.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_panel.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/settings_drawer.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_app_bar.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_input_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:garbanzo_ai/features/chat/widgets/panel_resize_handle.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_message_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_sidebar.dart';
import 'package:garbanzo_ai/features/chat/widgets/context_summary_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/context_window_indicator.dart';
import 'package:garbanzo_ai/features/chat/widgets/empty_chat_state.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_banner.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_activity_group.dart';

/// Main chat page with conversation sidebar and message area.
///
/// [ChatProvider], [ModelProvider], and the other user-scoped providers live
/// at the app level (see `main.dart`), so this page only binds the route's
/// [conversationId] to the provider — and mirrors provider changes back into
/// the URL so conversations are linkable on web.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.conversationId});

  /// Conversation id from the `/chat/:conversationId` route, if any.
  final String? conversationId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  ChatProvider? _provider;

  /// Conversation load requested by the URL but not yet reflected in the
  /// provider. While set, provider→URL sync is suspended so interim
  /// notifications (which still carry the old conversation) can't yank the
  /// URL back mid-load.
  String? _pendingLoad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<ChatProvider>();
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_syncUrlFromProvider);
      _provider = provider;
      provider.addListener(_syncUrlFromProvider);
      _loadFromUrl();
    }
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _loadFromUrl();
    }
  }

  @override
  void dispose() {
    _provider?.removeListener(_syncUrlFromProvider);
    super.dispose();
  }

  /// URL → provider: load the conversation named in the route when it
  /// differs from the one currently open.
  void _loadFromUrl() {
    final id = widget.conversationId;
    final provider = _provider;
    if (provider == null || id == null) return;
    if (id == provider.currentConversation?.id) return;
    _pendingLoad = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider?.loadConversation(id);
    });
  }

  /// Provider → URL: keep the address bar on the open conversation. All
  /// selection flows (sidebar tap, branch, auto-create on send, delete) go
  /// through the provider, so this single listener covers them all.
  void _syncUrlFromProvider() {
    if (!mounted) return;
    final provider = _provider;
    if (provider == null) return;
    final currentId = provider.currentConversation?.id;
    if (_pendingLoad != null) {
      if (currentId == _pendingLoad || provider.error != null) {
        _pendingLoad = null;
      } else {
        return;
      }
    }
    // Don't touch the URL while another page (settings, memory, …) is
    // pushed on top of the chat.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (currentId == widget.conversationId) return;
    GoRouter.of(context).go(currentId == null ? '/chat' : '/chat/$currentId');
  }

  @override
  Widget build(BuildContext context) => const _ChatPageContent();
}

class _ChatPageContent extends StatefulWidget {
  const _ChatPageContent();

  @override
  State<_ChatPageContent> createState() => _ChatPageContentState();
}

class _ChatPageContentState extends State<_ChatPageContent> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  bool _isDragOver = false;

  /// User-chosen width of the micro-app side panel (null = default). Adjusted
  /// by dragging the divider between the chat and the panel.
  double? _panelWidth;
  static const double _minPanelWidth = 320;
  static const double _minChatWidth = 360;

  // Smart auto-scroll: follow new content only when the user is already
  // reading the latest messages; never yank them away from scrollback.
  static const _nearBottomThreshold = 150.0;
  bool _showJumpToBottom = false;
  int _lastMessageCount = 0;
  String? _lastConversationId;
  ChatProvider? _chatProviderRef;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follow the live streaming bubble as it grows. Content updates flow
    // through the ValueNotifier (not notifyListeners), so the scroll
    // follow needs its own listener.
    final provider = context.read<ChatProvider>();
    if (!identical(provider, _chatProviderRef)) {
      _chatProviderRef?.streamingMessage.removeListener(_onStreamingUpdate);
      _chatProviderRef = provider;
      provider.streamingMessage.addListener(_onStreamingUpdate);
    }
  }

  @override
  void dispose() {
    _chatProviderRef?.streamingMessage.removeListener(_onStreamingUpdate);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= _nearBottomThreshold;
  }

  void _onScroll() {
    final show = !_isNearBottom;
    if (show != _showJumpToBottom) {
      setState(() => _showJumpToBottom = show);
    }
  }

  void _onStreamingUpdate() {
    if (_isNearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(animate: false);
      });
    }
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

  /// Context window the backend actually allocated for the last turn.
  ///
  /// Preferred over the model's maximum from the model list: the server caps
  /// the allocated window (num_ctx), so the model max would understate usage.
  int? _getLastContextLength(ChatProvider chatProvider) {
    final msgs = chatProvider.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      final meta = msgs[i].metadata;
      if (meta != null) {
        final c = meta['context_length'];
        if (c != null) return (c as num).toInt();
      }
    }
    return null;
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Streaming follow: jump instead of animating — at ~12 content
      // updates per second, overlapping animations would thrash.
      _scrollController.jumpTo(target);
    }
  }

  /// Scroll on structural changes only: jump on conversation switch, follow
  /// new messages when the user sent one or is already near the bottom.
  void _handleAutoScroll(ChatProvider chatProvider) {
    final messageCount = chatProvider.messages.length;
    final conversationId = chatProvider.currentConversation?.id;

    if (conversationId != _lastConversationId) {
      _lastConversationId = conversationId;
      _lastMessageCount = messageCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(animate: false);
      });
      return;
    }

    if (messageCount != _lastMessageCount) {
      final lastIsUser =
          chatProvider.messages.isNotEmpty && chatProvider.messages.last.isUser;
      final shouldScroll = lastIsUser || _isNearBottom;
      _lastMessageCount = messageCount;
      if (shouldScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
      }
    }
  }

  bool _showSidebar(BuildContext context) => context.isWide;

  /// Delete with an undo window: the provider defers the API call, and the
  /// snackbar's Undo restores the conversation before it fires.
  void _deleteWithUndo(ChatProvider chatProvider, String id) {
    chatProvider.deleteConversation(id);

    // Anchor the snackbar near the top of the window: SnackBars dock to the
    // bottom by default, so a large bottom margin lifts a floating one up,
    // while symmetric horizontal margins keep it from spanning the full width.
    final media = MediaQuery.of(context);
    final horizontalMargin = ((media.size.width - 420) / 2).clamp(16.0, 400.0);
    final bottomMargin = (media.size.height - media.padding.top - 88).clamp(
      80.0,
      2000.0,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Conversation deleted'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          margin: EdgeInsets.only(
            left: horizontalMargin,
            right: horizontalMargin,
            bottom: bottomMargin,
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => chatProvider.undoDeleteConversation(id),
          ),
        ),
      );
  }

  /// Handle dropped files: validate through the same [FilePickerHelper]
  /// rules as the file-picker path, then stage them as pending attachments.
  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    setState(() => _isDragOver = false);

    final chatProvider = context.read<ChatProvider>();
    if (!chatProvider.hasActiveConversation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a conversation first')),
      );
      return;
    }

    final rawFiles = <RawPickedFile>[];
    for (final file in files) {
      if (file is! File) continue;
      final bytes = await file.readAsBytes();
      rawFiles.add((name: file.path.split('/').last, bytes: bytes));
    }

    final result = FilePickerHelper.validate(
      files: rawFiles,
      existingNames: {...?chatProvider.pendingAttachments?.map((a) => a.name)},
    );
    if (!mounted) return;

    for (final error in result.validationErrors) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
    if (result.rejected.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Files too large:\n${result.rejected.join('\n')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (result.added.isNotEmpty) {
      chatProvider.addAttachments(result.added);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    _handleAutoScroll(chatProvider);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const SettingsDrawer(),
      body: DragTarget<List<dynamic>>(
        onWillAcceptWithDetails: (details) {
          final data = details.data;
          if (data.isEmpty) return false;
          setState(() => _isDragOver = true);
          return true;
        },
        onLeave: (_) {
          setState(() => _isDragOver = false);
        },
        onAcceptWithDetails: (details) => _handleDroppedFiles(details.data),
        builder: (context, candidateData, rejectedData) {
          return Stack(
            children: [
              Row(
                children: [
                  if (_showSidebar(context))
                    ChatSidebar(
                      conversations: chatProvider.conversations,
                      selectedConversationId:
                          chatProvider.currentConversation?.id,
                      onSelectConversation: (id) =>
                          chatProvider.loadConversation(id),
                      onDeleteConversation: (id) =>
                          _deleteWithUndo(chatProvider, id),
                      onNewChat: () => chatProvider.clearCurrentConversation(),
                      onTogglePin: (id) => chatProvider.togglePin(id),
                      isLoadingConversations:
                          chatProvider.isLoadingConversations,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        ChatAppBar(
                          onOpenSettings: () =>
                              _scaffoldKey.currentState?.openEndDrawer(),
                          onDeleteConversation: (id) =>
                              _deleteWithUndo(chatProvider, id),
                        ),
                        if (chatProvider.error != null)
                          _ErrorBanner(
                            message: chatProvider.error!,
                            onDismiss: chatProvider.clearError,
                          ),
                        Builder(
                          builder: (ctx) {
                            final tokensUsed = _getLastTokensPrompt(
                              chatProvider,
                            );
                            final contextLength =
                                _getLastContextLength(chatProvider) ??
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
                        Expanded(
                          child: Stack(
                            children: [
                              _buildMessageList(chatProvider, theme),
                              if (_showJumpToBottom)
                                Positioned(
                                  right: 16,
                                  bottom: 12,
                                  child: FloatingActionButton.small(
                                    heroTag: 'jump_to_bottom',
                                    tooltip: 'Jump to latest message',
                                    onPressed: () => _scrollToBottom(),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                                provider.sendMessage(
                                  message,
                                  attachments: merged,
                                );
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
                  // Wide layout: the live micro-app sits beside the chat in a
                  // panel the user can widen/narrow by dragging the divider.
                  if (chatProvider.panel.isOpen && context.isWide)
                    Builder(
                      builder: (context) {
                        final screenW = MediaQuery.of(context).size.width;
                        final maxW = (screenW - _minChatWidth).clamp(
                          _minPanelWidth,
                          screenW,
                        );
                        // Default to a big portion of the screen (Claude-canvas
                        // style): the panel is the dominant pane, chat sits beside.
                        final defaultW = (screenW * 0.6).clamp(
                          _minPanelWidth,
                          maxW,
                        );
                        final width = (_panelWidth ?? defaultW).clamp(
                          _minPanelWidth,
                          maxW,
                        );
                        return SizedBox(
                          width: width,
                          child: Row(
                            children: [
                              PanelResizeHandle(
                                onDrag: (dx) => setState(
                                  () => _panelWidth = (width - dx).clamp(
                                    _minPanelWidth,
                                    maxW,
                                  ),
                                ),
                                onReset: () =>
                                    setState(() => _panelWidth = null),
                              ),
                              Expanded(
                                child: MicroAppPanel(panel: chatProvider.panel),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
              // Narrow layout: the micro-app takes over as a full-screen overlay.
              if (chatProvider.panel.isOpen && context.isNarrow)
                Positioned.fill(
                  child: MicroAppPanel(
                    panel: chatProvider.panel,
                    showCloseAsBack: true,
                  ),
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

    final showSystemPrompt = context.watch<SettingsProvider>().showSystemPrompt;
    final summary = chatProvider.currentConversation?.contextSummary;
    final hasSummary = summary != null && summary.isNotEmpty;
    final hasBanner =
        showSystemPrompt && chatProvider.currentConversation != null;

    var itemOffset = 0;
    if (hasBanner) itemOffset++;
    if (hasSummary) itemOffset++;

    // Group consecutive tool_call/tool_result messages so they render as a
    // single collapsible "tool activity" section instead of N stacked cards.
    final items = <_ListItem>[];
    final messages = chatProvider.messages;
    var i = 0;
    var lastAssistantIdx = -1;
    for (var j = 0; j < messages.length; j++) {
      if (messages[j].isAssistant) lastAssistantIdx = j;
    }
    while (i < messages.length) {
      final m = messages[i];
      if (m.isToolCall || m.isToolResult) {
        final start = i;
        while (i < messages.length &&
            (messages[i].isToolCall || messages[i].isToolResult)) {
          i++;
        }
        items.add(_ToolGroupItem(messages.sublist(start, i), endIdx: i - 1));
      } else {
        items.add(_MessageItem(m, idx: i));
        i++;
      }
    }

    // Every list item lives in a centered reading column so wide desktop
    // windows don't stretch prose to unreadable line lengths.
    Widget centered(Widget child) => ReadingColumn(child: child);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: items.length + itemOffset,
      itemBuilder: (context, index) {
        var leadingIdx = 0;
        if (hasBanner) {
          if (index == leadingIdx) return centered(const SystemPromptBanner());
          leadingIdx++;
        }
        if (hasSummary) {
          if (index == leadingIdx) {
            return centered(ContextSummaryWidget(summary: summary));
          }
        }
        final item = items[index - itemOffset];
        if (item is _ToolGroupItem) {
          // Streaming when this group is the trailing item AND a stream
          // is in flight (means the model is still working on the loop).
          final isTrailing = item.endIdx == messages.length - 1;
          return FadeSlideIn(
            child: centered(
              ToolActivityGroup(
                messages: item.messages,
                isStreaming: isTrailing && chatProvider.isSending,
              ),
            ),
          );
        }
        final messageItem = item as _MessageItem;
        final message = messageItem.message;
        final msgIdx = messageItem.idx;
        final isLastMessage = msgIdx == messages.length - 1;

        Widget buildBubble(ChatMessage m) => FadeSlideIn(
          child: centered(
            ChatMessageWidget(
              message: m,
              isStreaming:
                  isLastMessage && chatProvider.isSending && m.isAssistant,
              conversationId: chatProvider.currentConversation?.id,
              isLastAssistant: m.isAssistant && msgIdx == lastAssistantIdx,
            ),
          ),
        );

        // The in-flight assistant bubble subscribes to the streaming
        // channel directly, so per-chunk updates repaint only this one
        // widget instead of the whole list.
        if (message.id == chatProvider.streamingMessageId) {
          return ValueListenableBuilder<ChatMessage?>(
            valueListenable: chatProvider.streamingMessage,
            builder: (context, live, _) => buildBubble(
              live != null && live.id == message.id ? live : message,
            ),
          );
        }
        return buildBubble(message);
      },
    );
  }
}

sealed class _ListItem {
  const _ListItem();
}

class _MessageItem extends _ListItem {
  const _MessageItem(this.message, {required this.idx});
  final ChatMessage message;
  final int idx;
}

class _ToolGroupItem extends _ListItem {
  const _ToolGroupItem(this.messages, {required this.endIdx});
  final List<ChatMessage> messages;
  final int endIdx;
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
          Icon(
            Icons.error_outline,
            color: colorScheme.onErrorContainer,
            size: 20,
          ),
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
            tooltip: 'Dismiss error',
            icon: Icon(
              Icons.close,
              color: colorScheme.onErrorContainer,
              size: 20,
            ),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
