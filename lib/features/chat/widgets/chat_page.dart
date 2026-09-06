import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/platform_info.dart';
import 'package:garbanzo_ai/core/reading_column.dart';
import 'package:garbanzo_ai/core/smart_scroll_controller.dart';
import 'package:garbanzo_ai/core/widgets/fade_slide_in.dart';
import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_panel.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/settings_drawer.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_app_bar.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_input_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:garbanzo_ai/features/chat/widgets/panel_resize_handle.dart';
import 'package:garbanzo_ai/features/chat/widgets/response_recovery_notice.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_message_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_sidebar.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_drawer.dart';
import 'package:garbanzo_ai/features/chat/widgets/context_summary_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/context_window_indicator.dart';
import 'package:garbanzo_ai/features/chat/widgets/empty_chat_state.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_landing.dart';
import 'package:garbanzo_ai/features/chat/widgets/topic_banner.dart';
import 'package:garbanzo_ai/features/topics/widgets/active_context_panel.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_context_empty_state.dart';
import 'package:garbanzo_ai/features/chat/widgets/system_prompt_banner.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_activity_group.dart';
import 'package:garbanzo_ai/features/chat/widgets/vision_model_warning_dialog.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_chat_view.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Main chat page with conversation sidebar and message area.
///
/// [ChatProvider], [ModelProvider], and the other user-scoped providers live
/// at the app level (see `main.dart`), so this page only binds the route's
/// [conversationId] to the provider — and mirrors provider changes back into
/// the URL so conversations are linkable on web.
///
/// This page is also the shell for rooms: `/rooms/:roomId` renders it with
/// [roomId] set, which swaps the content pane to a [RoomChatView] while the
/// sidebar stays in place — no separate rooms page.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.conversationId, this.roomId});

  /// Conversation id from the `/chat/:conversationId` route, if any.
  final String? conversationId;

  /// Room id from the `/rooms/:roomId` route, if any. Mutually exclusive
  /// with [conversationId].
  final String? roomId;

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
    if (provider == null) return;
    if (id == null && widget.roomId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _provider?.enterPrimaryConversation();
      });
      return;
    }
    if (id == null) return;
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
    // While a room fills the content pane the conversation is not on screen,
    // so provider changes must not yank the URL away from /rooms/:id.
    // Conversation clicks navigate explicitly in that state.
    if (widget.roomId != null) return;
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
    final conv = provider.currentConversation;
    final topicDiscovery = context.read<TopicDiscoveryProvider>();
    final targetTopic = conv?.activeTopic;
    if (targetTopic != topicDiscovery.selectedTopic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<TopicDiscoveryProvider>().setSelectedTopic(targetTopic);
        }
      });
    }

    // Don't touch the URL while another page (settings, memory, …) is
    // pushed on top of the chat.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (currentId == widget.conversationId) return;
    GoRouter.of(context).go(currentId == null ? '/chat' : '/chat/$currentId');
  }

  @override
  Widget build(BuildContext context) => _ChatPageContent(roomId: widget.roomId);
}

class _ChatPageContent extends StatefulWidget {
  const _ChatPageContent({this.roomId});

  final String? roomId;

  @override
  State<_ChatPageContent> createState() => _ChatPageContentState();
}

class _ChatPageContentState extends State<_ChatPageContent>
    with WidgetsBindingObserver {
  static const _syncInterval = Duration(seconds: 10);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Smart auto-scroll (streaming follow with reader-friendly release,
  /// jump-to-bottom pill, keyboard follow) — shared with the rooms view.
  final SmartScrollController _scroll = SmartScrollController();
  ScrollController get _scrollController => _scroll.controller;
  Timer? _syncTimer;
  bool _isDragOver = false;
  bool _visionWarningScheduled = false;
  bool _visionWarningOpen = false;
  bool _showActiveContext = true;

  /// User-chosen width of the micro-app side panel (null = default). Adjusted
  /// by dragging the divider between the chat and the panel.
  double? _panelWidth;
  static const double _minPanelWidth = 320;
  static const double _minChatWidth = 360;

  // Smart auto-scroll: follow new content only when the user is already
  // reading the latest messages; never yank them away from scrollback.
  ChatProvider? _chatProviderRef;

  @override
  void initState() {
    super.initState();
    _scroll.attach();
    // Page in older messages when the user scrolls near the top (the smart
    // controller owns its own listener for the jump-pill flag).
    _scrollController.addListener(_maybeLoadOlderMessages);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    _scroll.handleKeyboardInset(View.of(context).viewInsets.bottom);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSyncTimer();
      _syncNow();
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
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
    _startSyncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _chatProviderRef?.streamingMessage.removeListener(_onStreamingUpdate);
    _scrollController.removeListener(_maybeLoadOlderMessages);
    _scroll.dispose();
    super.dispose();
  }

  void _startSyncTimer() {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _syncTimer ??= Timer.periodic(_syncInterval, (_) => _syncNow());
  }

  void _syncNow() {
    final provider = _chatProviderRef;
    if (provider != null) unawaited(provider.syncFromServer());
  }

  // B-03: page in older messages once the user scrolls near the top,
  // instead of loading a whole multi-hundred-message history up front.
  static const _nearTopThreshold = 300.0;

  void _maybeLoadOlderMessages() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > _nearTopThreshold) return;

    final provider = context.read<ChatProvider>();
    if (!provider.hasMoreMessages || provider.loadingOlderMessages) return;

    // Prepending messages shifts everything currently on screen down by the
    // height of what got inserted above it — jump the scroll offset by that
    // same delta after the frame so the view doesn't visibly yank.
    final previousMaxExtent = position.maxScrollExtent;
    final previousPixels = position.pixels;
    unawaited(
      provider.loadOlderMessages().then((_) {
        if (!mounted || !_scrollController.hasClients) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final delta =
              _scrollController.position.maxScrollExtent - previousMaxExtent;
          if (delta > 0) {
            _scrollController.jumpTo(previousPixels + delta);
          }
        });
      }),
    );
  }

  /// Streaming tick: hand the update to the shared smart-scroll helper, which
  /// chases the growing bubble until its top can reach the viewport top, then
  /// pins it there once and releases the scroll to the user.
  void _onStreamingUpdate() {
    _scroll.handleStreamingTick(_chatProviderRef?.streamingMessageId);
  }

  int? _lastMeta(ChatProvider p, String key) {
    for (var i = p.messages.length - 1; i >= 0; i--) {
      final v = p.messages[i].metadata?[key];
      if (v != null) return (v as num).toInt();
    }
    return null;
  }

  int? _getLastTokensPrompt(ChatProvider c) => _lastMeta(c, 'tokens_prompt');
  int? _getLastContextLength(ChatProvider c) => _lastMeta(c, 'context_length');

  /// Scroll on structural changes only: jump on conversation switch, follow
  /// new messages when the user sent one or is already near the bottom.
  /// Delegates to the shared smart-scroll helper (keyed by conversation id).
  void _handleAutoScroll(ChatProvider chatProvider) {
    final messages = chatProvider.messages;
    _scroll.handleStructural(
      itemCount: messages.length,
      containerId: chatProvider.currentConversation?.id,
      forceFollow: messages.isNotEmpty && messages.last.isUser,
    );
  }

  bool _showSidebar(BuildContext context) => context.isWide;

  // ------------------------------------------------------- shell navigation
  //
  // With a room active the conversation URL sync is suspended (see
  // ChatPage._syncUrlFromProvider), so selection handlers navigate explicitly
  // to swap the content pane back to a conversation.

  void _selectConversation(String id) async {
    if (widget.roomId != null) {
      context.go('/chat/$id');
    } else {
      await context.read<ChatProvider>().loadConversation(id);
      if (!mounted) return;
      final conv = context.read<ChatProvider>().currentConversation;
      context.read<TopicDiscoveryProvider>().setSelectedTopic(
        conv?.activeTopic,
      );
    }
  }

  void _newChat() {
    context.read<TopicDiscoveryProvider>().setSelectedTopic(null);
    context.read<ChatProvider>().clearCurrentConversation();
    if (widget.roomId != null) context.go('/chat');
  }

  void _openPrimary() {
    final chat = context.read<ChatProvider>();
    context.go('/chat');
    unawaited(chat.enterPrimaryConversation());
  }

  void _newTopic() {
    context.read<TopicDiscoveryProvider>().startNewTopic();
    _openPrimary();
  }

  void _openActiveContext() {
    final conversation = context.read<ChatProvider>().currentConversation;
    if (conversation == null) return;
    final isTopic =
        conversation.isPrimary || conversation.activeTopicId != null;
    if (!isTopic) return;
    if (context.isWide) {
      setState(() => _showActiveContext = !_showActiveContext);
      return;
    }
    unawaited(
      ActiveContextPanel.showSheet(
        context,
        conversationId: conversation.id,
        onRedirect: _newTopic,
      ),
    );
  }

  void _selectRoom(String id) {
    if (id == widget.roomId) return;
    context.go('/rooms/$id');
  }

  Future<void> _deleteRoom(String id) async {
    final wasActive = id == widget.roomId;
    try {
      await context.read<RoomProvider>().deleteRoom(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.messageFailedToDeleteRoom(e.toString()),
            ),
          ),
        );
      }
      return;
    }
    if (wasActive && mounted) context.go('/chat');
  }

  /// Narrow-layout drawer opened from the room header (the chat app bar has
  /// its own trigger).
  void _openMobileDrawer() {
    final chatProvider = context.read<ChatProvider>();
    showMobileConversationDrawer(
      context: context,
      conversations: chatProvider.conversations,
      selectedId: chatProvider.currentConversation?.id,
      onSelect: _selectConversation,
      onDelete: (id) => _deleteWithUndo(chatProvider, id),
      onNewChat: _newChat,
      onTogglePin: (id) => chatProvider.togglePin(id),
      onMuteConversation: (id, duration) => chatProvider.setMute(id, duration),
      initialTab: 1,
      selectedRoomId: widget.roomId,
      onSelectRoom: _selectRoom,
      onDeleteRoom: _deleteRoom,
    );
  }

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
          content: Text(
            AppLocalizations.of(context)!.messageConversationDeleted,
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          margin: EdgeInsets.only(
            left: horizontalMargin,
            right: horizontalMargin,
            bottom: bottomMargin,
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.labelUndo,
            onPressed: () => chatProvider.undoDeleteConversation(id),
          ),
        ),
      );
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        behavior: error ? SnackBarBehavior.floating : null,
      ),
    );
  }

  Future<void> _stageFiles(
    List<RawPickedFile> raw,
    ChatProvider provider,
  ) async {
    final result = await FilePickerHelper.validate(
      files: raw,
      existingNames: {...?provider.pendingAttachments?.map((a) => a.name)},
    );
    if (!mounted) return;
    for (final e in result.validationErrors) {
      _snack(e);
    }
    if (result.rejected.isNotEmpty) {
      _snack(
        AppLocalizations.of(
          context,
        )!.messageFilesTooLarge(result.rejected.join('\n')),
        error: true,
      );
    }
    if (result.added.isNotEmpty) provider.addAttachments(result.added);
  }

  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    setState(() => _isDragOver = false);
    final chatProvider = context.read<ChatProvider>();
    if (!chatProvider.hasActiveConversation) {
      _snack(AppLocalizations.of(context)!.messageStartAConversationFirst);
      return;
    }
    final raw = <RawPickedFile>[];
    for (final f in files) {
      if (f is! File) continue;
      raw.add((name: f.path.split('/').last, bytes: await f.readAsBytes()));
    }
    await _stageFiles(raw, chatProvider);
  }

  Future<void> _handleOsDrop(List<DropItem> items) async {
    setState(() => _isDragOver = false);
    if (widget.roomId != null) return;
    final chatProvider = context.read<ChatProvider>();
    final folder = items
        .where((i) => FileSystemEntity.isDirectorySync(i.path))
        .firstOrNull;
    if (folder != null) {
      try {
        await chatProvider.attachClientFolder(
          chatProvider.currentConversation?.id,
          folder.path,
        );
      } catch (_) {
        if (mounted) {
          _snack(AppLocalizations.of(context)!.messageFolderAttachFailed);
        }
      }
      return;
    }
    await _handleDroppedFiles([for (final i in items) File(i.path)]);
  }

  /// Wrap [child] in a desktop [DropTarget] so OS-level file/folder drops reach
  /// [_handleOsDrop]. On mobile/web or in a room, returns [child] unchanged —
  /// the native in-app [DragTarget] still handles those cases.
  Widget _wrapDesktopDrop(Widget child) {
    if (!PlatformInfo.isDesktop || widget.roomId != null) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      onDragDone: (detail) => _handleOsDrop(detail.files),
      child: child,
    );
  }

  void _scheduleVisionModelWarning(
    ChatProvider chatProvider,
    ModelProvider modelProvider,
    String currentModelName,
  ) {
    if (_visionWarningScheduled || _visionWarningOpen) return;
    _visionWarningScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _visionWarningScheduled = false;
      if (!mounted ||
          chatProvider.errorType != 'unsupported_image_input' ||
          _visionWarningOpen) {
        return;
      }

      _visionWarningOpen = true;
      final choice = await showDialog<VisionModelChoice>(
        context: context,
        builder: (_) => VisionModelWarningDialog(
          currentModelName: currentModelName,
          choices: modelProvider.visionModelChoices(
            currentModelId: chatProvider.currentConversation?.model,
            preferThinking:
                chatProvider.currentConversation?.thinkingLevel != null,
          ),
        ),
      );
      _visionWarningOpen = false;
      if (!mounted) return;

      if (choice == null) {
        chatProvider.clearError();
      } else {
        await chatProvider.switchModelAndRetryLastTurn(choice.model.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final currentModelId = chatProvider.currentConversation?.model;
    final currentModel = modelProvider.availableModels
        .where((model) => model.id == currentModelId)
        .firstOrNull;
    if (chatProvider.errorType == 'unsupported_image_input') {
      _scheduleVisionModelWarning(
        chatProvider,
        modelProvider,
        currentModel?.name ?? currentModelId ?? l10n.labelModel,
      );
    }

    _handleAutoScroll(chatProvider);

    // The Android back gesture must close the micro-app overlay (narrow
    // layouts only) instead of backing out of the app.
    final panelOverlayOpen = chatProvider.panel.isOpen && context.isNarrow;

    return PopScope(
      canPop: !panelOverlayOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) chatProvider.panel.close();
      },
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: const SettingsDrawer(),
        body: _wrapDesktopDrop(
          DragTarget<List<dynamic>>(
            onWillAcceptWithDetails: (details) {
              // Attachments belong to conversations; ignore drops on a room.
              if (widget.roomId != null) return false;
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
                          onSelectConversation: _selectConversation,
                          onDeleteConversation: (id) =>
                              _deleteWithUndo(chatProvider, id),
                          onNewChat: _newChat,
                          onTogglePin: (id) => chatProvider.togglePin(id),
                          onMuteConversation: (id, duration) =>
                              chatProvider.setMute(id, duration),
                          isLoadingConversations:
                              chatProvider.isLoadingConversations,
                          selectedRoomId: widget.roomId,
                          initialTab: widget.roomId != null ? 2 : 1,
                          onOpenPrimary: _openPrimary,
                          onSelectRoom: _selectRoom,
                          onDeleteRoom: _deleteRoom,
                        ),
                      if (widget.roomId != null)
                        Expanded(
                          child: RoomChatView(
                            roomId: widget.roomId!,
                            onOpenSettings: () =>
                                _scaffoldKey.currentState?.openEndDrawer(),
                            onOpenDrawer: _showSidebar(context)
                                ? null
                                : _openMobileDrawer,
                          ),
                        )
                      else
                        Expanded(
                          child: Column(
                            children: [
                              ChatAppBar(
                                onOpenSettings: () =>
                                    _scaffoldKey.currentState?.openEndDrawer(),
                                onDeleteConversation: (id) =>
                                    _deleteWithUndo(chatProvider, id),
                                onNewChat:
                                    chatProvider
                                            .currentConversation
                                            ?.isPrimary ==
                                        true
                                    ? _newTopic
                                    : _newChat,
                              ),
                              if (chatProvider.error != null &&
                                  chatProvider.errorType !=
                                      'unsupported_image_input')
                                _ErrorBanner(
                                  message: chatProvider.error!,
                                  onDismiss: chatProvider.clearError,
                                ),
                              if (chatProvider.responseRecoveryState != null)
                                ResponseRecoveryNotice(
                                  state: chatProvider.responseRecoveryState!,
                                ),
                              Builder(
                                builder: (ctx) {
                                  final tokensUsed = _getLastTokensPrompt(
                                    chatProvider,
                                  );
                                  final contextLength =
                                      _getLastContextLength(chatProvider) ??
                                      modelProvider
                                          .selectedModel
                                          ?.contextLength;
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
                              if (chatProvider.currentConversation?.isPrimary ==
                                      true &&
                                  !context
                                      .watch<TopicDiscoveryProvider>()
                                      .showLanding)
                                const TopicBanner(),
                              Expanded(
                                child: Stack(
                                  children: [
                                    _buildMessageList(chatProvider, theme),
                                    ValueListenableBuilder<bool>(
                                      valueListenable: _scroll.showJumpToBottom,
                                      builder: (context, show, _) => show
                                          ? Positioned(
                                              right: 16,
                                              bottom: 12,
                                              child: FloatingActionButton.small(
                                                heroTag: 'jump_to_bottom',
                                                tooltip:
                                                    'Jump to latest message',
                                                onPressed: _scroll.resumeFollow,
                                                child: const Icon(
                                                  Icons.keyboard_arrow_down,
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                              Consumer<ChatProvider>(
                                builder: (context, provider, _) {
                                  return ChatInputWidget(
                                    onSend: (message, attachments) async {
                                      // Merge any pending attachments from drag-drop
                                      final merged = [...attachments];
                                      if (provider.pendingAttachments != null) {
                                        merged.addAll(
                                          provider.pendingAttachments!,
                                        );
                                        provider.clearPendingAttachments();
                                      }
                                      final selectedTopic = context
                                          .read<TopicDiscoveryProvider>()
                                          .selectedTopic;
                                      if (provider
                                                  .currentConversation
                                                  ?.isPrimary ==
                                              true &&
                                          selectedTopic != null) {
                                        await provider.createConversation(
                                          title: selectedTopic.label,
                                          activeTopicId: selectedTopic.id,
                                          initialMessage: message,
                                          initialAttachments: merged,
                                        );
                                      } else {
                                        await provider.sendMessage(
                                          message,
                                          attachments: merged,
                                        );
                                      }
                                    },
                                    onStop: () => chatProvider.stopStreaming(),
                                    isLoading: chatProvider.isSending,
                                    initialAttachments:
                                        provider.pendingAttachments,
                                    isPrimary:
                                        provider
                                            .currentConversation
                                            ?.isPrimary ==
                                        true,
                                    onNewTopic: _newTopic,
                                    onOpenContext: _openActiveContext,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      if (widget.roomId == null &&
                          (chatProvider.currentConversation?.isPrimary ==
                                  true ||
                              chatProvider.currentConversation?.activeTopicId !=
                                  null) &&
                          !context
                              .watch<TopicDiscoveryProvider>()
                              .showLanding &&
                          _showActiveContext &&
                          context.isWide)
                        SizedBox(
                          width: 340,
                          child: ActiveContextPanel(
                            conversationId:
                                chatProvider.currentConversation!.id,
                            onRedirect: _newTopic,
                            onClose: () =>
                                setState(() => _showActiveContext = false),
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
                                    // Accumulate each drag delta against
                                    // `_panelWidth` (the state) — NOT against
                                    // `width` (the rendered snapshot captured
                                    // by this closure at build time). Multiple
                                    // `onHorizontalDragUpdate` events can fire
                                    // within one frame before the rebuild
                                    // lands; reading the stale `width` here
                                    // made consecutive deltas overwrite each
                                    // other instead of accumulating, so the
                                    // panel barely moved even on a long drag.
                                    onDrag: (dx) => setState(() {
                                      final current = _panelWidth ?? defaultW;
                                      _panelWidth = (current + dx).clamp(
                                        _minPanelWidth,
                                        maxW,
                                      );
                                    }),
                                    onReset: () =>
                                        setState(() => _panelWidth = null),
                                  ),
                                  Expanded(
                                    child: MicroAppPanel(
                                      panel: chatProvider.panel,
                                    ),
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
                                    AppLocalizations.of(
                                      context,
                                    )!.messageDropFilesHere,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
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
        ),
      ),
    );
  }

  Widget _buildMessageList(ChatProvider chatProvider, ThemeData theme) {
    final conversation = chatProvider.currentConversation;
    final topicDiscovery = context.watch<TopicDiscoveryProvider>();
    if (conversation?.isPrimary == true && topicDiscovery.showLanding) {
      return TopicLanding(
        conversationId: conversation!.id,
        onStarterSelected: (message) async {
          final selectedTopic = topicDiscovery.selectedTopic;
          if (selectedTopic != null) {
            await chatProvider.createConversation(
              title: selectedTopic.label,
              activeTopicId: selectedTopic.id,
              initialMessage: message,
            );
          } else {
            await chatProvider.sendMessage(message);
          }
        },
      );
    }
    if (chatProvider.messages.isEmpty &&
        chatProvider.currentConversation == null) {
      return EmptyChatState(
        onSendMessage: (msg) => chatProvider.sendMessage(msg),
      );
    }

    final hasUserMessages = chatProvider.messages.any((m) => m.role == 'user');

    final activeTopic =
        conversation?.activeTopic ??
        (conversation?.activeTopicId != null &&
                topicDiscovery.selectedTopic?.id == conversation?.activeTopicId
            ? topicDiscovery.selectedTopic
            : (topicDiscovery.selectedTopic ??
                  (conversation?.activeTopicId != null
                      ? TopicNode(
                          id: conversation!.activeTopicId!,
                          label: conversation.title ?? 'Topic',
                          origin: TopicOrigin.history,
                          description: conversation.contextSummary,
                          starterPrompts: [
                            'Continue with ${conversation.title ?? 'Topic'}',
                            'What should I do next about ${conversation.title ?? 'Topic'}?',
                          ],
                        )
                      : null)));

    if (!hasUserMessages && activeTopic != null && conversation != null) {
      return TopicContextEmptyState(
        conversationId: conversation.id,
        topic: activeTopic,
        onStarterSelected: (message) async {
          if (conversation.isPrimary) {
            await chatProvider.createConversation(
              title: activeTopic.label,
              activeTopicId: activeTopic.id,
              initialMessage: message,
            );
          } else {
            await chatProvider.sendMessage(message);
          }
        },
        onOpenContext: _openActiveContext,
      );
    }

    if (chatProvider.messages.isEmpty && chatProvider.isLoadingConversations) {
      return const Center(child: CircularProgressIndicator());
    }

    final showSystemPrompt = context.watch<SettingsProvider>().showSystemPrompt;
    final isTopicChat =
        chatProvider.currentConversation?.isPrimary == true ||
        chatProvider.currentConversation?.activeTopicId != null ||
        context.watch<TopicDiscoveryProvider>().selectedTopic != null;
    final summary = isTopicChat
        ? null
        : chatProvider.currentConversation?.contextSummary;
    final hasSummary = summary != null && summary.isNotEmpty;
    final hasBanner =
        showSystemPrompt && chatProvider.currentConversation != null;
    // B-03: a spinner above the oldest loaded message while an older page
    // fetched via scroll-to-top (see _maybeLoadOlderMessages) is in flight.
    final showLoadingOlder = chatProvider.loadingOlderMessages;

    var itemOffset = 0;
    if (showLoadingOlder) itemOffset++;
    if (hasBanner) itemOffset++;
    if (hasSummary) itemOffset++;

    // Group consecutive tool_call/tool_result messages so they render as a
    // single collapsible "tool activity" section instead of N stacked cards.
    final items = <_ListItem>[];
    final messages = chatProvider.messages;
    // A proposal tool's result is a card the user acts on, not a step in the
    // agent's timeline — folding it into the collapsible "Used N tools"
    // section would bury it (and make ChatMessageWidget's card branch
    // unreachable), so it stays a top-level item.
    bool isGroupableTool(ChatMessage m) =>
        (m.isToolCall || m.isToolResult) && m.actionProposal == null;

    var i = 0;
    var lastAssistantIdx = -1;
    for (var j = 0; j < messages.length; j++) {
      if (messages[j].isAssistant) lastAssistantIdx = j;
    }
    while (i < messages.length) {
      final m = messages[i];
      if (isGroupableTool(m)) {
        final start = i;
        while (i < messages.length && isGroupableTool(messages[i])) {
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
        if (showLoadingOlder) {
          if (index == leadingIdx) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          leadingIdx++;
        }
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
          // The streaming assistant placeholder stays anchored after tool
          // messages, so an active tool group is technically penultimate.
          // Treat it as live while everything after it is that still-empty
          // placeholder; once answer text arrives the activity is complete.
          final messagesAfter = messages.skip(item.endIdx + 1);
          final isActive =
              chatProvider.isSending &&
              messagesAfter.every(
                (message) =>
                    message.id == chatProvider.streamingMessageId &&
                    message.isAssistant &&
                    message.content.isEmpty,
              );
          return FadeSlideIn(
            child: centered(
              ToolActivityGroup(messages: item.messages, isStreaming: isActive),
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
              onOpenTopicContext: _openActiveContext,
            ),
          ),
        );

        // The in-flight assistant bubble subscribes to the streaming
        // channel directly, so per-chunk updates repaint only this one
        // widget instead of the whole list. The anchor key lets the smart
        // scroll helper locate the bubble to chase/pin it while streaming.
        if (message.id == chatProvider.streamingMessageId) {
          return KeyedSubtree(
            key: _scroll.streamAnchorKey,
            child: ValueListenableBuilder<ChatMessage?>(
              valueListenable: chatProvider.streamingMessage,
              builder: (context, live, _) => buildBubble(
                live != null && live.id == message.id ? live : message,
              ),
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
      constraints: const BoxConstraints(maxHeight: 120),
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.error_outline,
              color: colorScheme.onErrorContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
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
