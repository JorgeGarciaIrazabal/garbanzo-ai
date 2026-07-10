import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth_service.dart';
import '../../../core/responsive.dart';
import '../../memory/providers/memory_provider.dart';
import '../../microapps/widgets/micro_app_panel.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/widgets/settings_drawer.dart';
import '../../tools/providers/tool_provider.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../providers/search_provider.dart';
import '../providers/system_prompt_provider.dart';
import 'chat_input_widget.dart';
import 'chat_message_widget.dart';
import 'chat_sidebar.dart';
import 'context_summary_widget.dart';
import 'context_window_indicator.dart';
import 'empty_chat_state.dart';
import 'mobile_drawer.dart';
import 'model_selector_widget.dart';
import 'system_prompt_banner.dart';
import 'tool_activity_group.dart';

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
              ChangeNotifierProvider(create: (_) => SystemPromptProvider()),
              ChangeNotifierProvider(create: (_) => ToolProvider()),
              ChangeNotifierProvider(create: (_) => SearchProvider()),
              ChangeNotifierProvider(create: (_) => NotificationProvider()),
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
      final lastIsUser = chatProvider.messages.isNotEmpty &&
          chatProvider.messages.last.isUser;
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Conversation deleted'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => chatProvider.undoDeleteConversation(id),
          ),
        ),
      );
  }

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

    _handleAutoScroll(chatProvider);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: SettingsDrawer(onLogout: widget.onLogout),
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
                  ChatSidebar(
                    conversations: chatProvider.conversations,
                    selectedConversationId: chatProvider.currentConversation?.id,
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
                                  child:
                                      const Icon(Icons.keyboard_arrow_down),
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
                // Wide layout: the live micro-app sits beside the chat in a
                // panel the user can widen/narrow by dragging the divider.
                if (chatProvider.panel.isOpen && context.isWide)
                  Builder(builder: (context) {
                    final screenW = MediaQuery.of(context).size.width;
                    final maxW =
                        (screenW - _minChatWidth).clamp(_minPanelWidth, screenW);
                    // Default to a big portion of the screen (Claude-canvas
                    // style): the panel is the dominant pane, chat sits beside.
                    final defaultW =
                        (screenW * 0.6).clamp(_minPanelWidth, maxW);
                    final width =
                        (_panelWidth ?? defaultW).clamp(_minPanelWidth, maxW);
                    return SizedBox(
                      width: width,
                      child: Row(
                        children: [
                          _PanelResizeHandle(
                            onDrag: (dx) => setState(
                              () => _panelWidth =
                                  (width - dx).clamp(_minPanelWidth, maxW),
                            ),
                            onReset: () => setState(() => _panelWidth = null),
                          ),
                          Expanded(
                            child: MicroAppPanel(panel: chatProvider.panel),
                          ),
                        ],
                      ),
                    );
                  }),
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
                onDelete: (id) => _deleteWithUndo(chatProvider, id),
                onNewChat: () => chatProvider.clearCurrentConversation(),
                onTogglePin: (id) => chatProvider.togglePin(id),
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
        const NotificationBell(),
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

    final showSystemPrompt =
        context.watch<SettingsProvider>().showSystemPrompt;
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
    Widget centered(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: child,
            ),
          ),
        );

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
          return centered(ToolActivityGroup(
            messages: item.messages,
            isStreaming: isTrailing && chatProvider.isSending,
          ));
        }
        final messageItem = item as _MessageItem;
        final message = messageItem.message;
        final msgIdx = messageItem.idx;
        final isLastMessage = msgIdx == messages.length - 1;

        Widget buildBubble(ChatMessage m) => centered(ChatMessageWidget(
              message: m,
              isStreaming: isLastMessage &&
                  chatProvider.isSending &&
                  m.isAssistant,
              conversationId: chatProvider.currentConversation?.id,
              isLastAssistant:
                  m.isAssistant && msgIdx == lastAssistantIdx,
            ));

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

/// Draggable divider that resizes the micro-app side panel. Drag left/right to
/// widen/narrow; double-click to reset to the default width.
class _PanelResizeHandle extends StatelessWidget {
  const _PanelResizeHandle({required this.onDrag, required this.onReset});

  /// Called with the horizontal drag delta (dx) on each move.
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onDoubleTap: onReset,
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 1,
              color: theme.dividerColor,
              child: Center(
                child: Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
