import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/core/responsive.dart';
import 'package:garbanzo_ai/core/smart_scroll_controller.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_auto_play_tracker.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/services/transcript_export_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_app_bar.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_drop_zone.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_input_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_page_actions.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_sidebar.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_transcript_view.dart';
import 'package:garbanzo_ai/features/chat/widgets/context_window_indicator.dart';
import 'package:garbanzo_ai/features/chat/widgets/mobile_drawer.dart';
import 'package:garbanzo_ai/features/chat/widgets/response_recovery_notice.dart';
import 'package:garbanzo_ai/features/chat/widgets/topic_banner.dart';
import 'package:garbanzo_ai/features/chat/widgets/vision_model_warning_dialog.dart';
import 'package:garbanzo_ai/features/chat/widgets/workflow_completion_notice.dart';
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_panel.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_chat_view.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/settings_drawer.dart';
import 'package:garbanzo_ai/features/topics/providers/active_context_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/topics/widgets/active_context_panel.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

@visibleForTesting
Future<void> submitChatComposerMessage({
  required ChatProvider chatProvider,
  required TopicDiscoveryProvider topicDiscovery,
  required String message,
  required List<ChatAttachment> attachments,
}) async {
  if (topicDiscovery.startingTopic || chatProvider.isSending) return;
  // The landing map is the "no topic chosen yet" surface: every explicit
  // selection closes it (setSelectedTopic/activate set showLanding false), so
  // while it is visible a send starts a clean regular thread. Do not key this
  // on `selectedTopic` — the delayed server sync (synchronizeSelectedTopic)
  // repopulates it from the primary's persisted active topic without closing
  // the landing, which would append the message to the primary's loaded
  // history instead of opening an empty thread (user report 41c79409).
  final startsRegularThread =
      chatProvider.currentConversation?.isPrimary == true &&
      topicDiscovery.showLanding;
  if (startsRegularThread) {
    await chatProvider.createConversation(
      initialMessage: message,
      initialAttachments: attachments,
    );
    return;
  }
  await chatProvider.sendMessage(message, attachments: attachments);
}

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
    context.read<ActiveContextProvider>().bindConversation(conv?.id);
    final topicDiscovery = context.read<TopicDiscoveryProvider>();
    final targetTopic = conv?.activeTopic;
    if (targetTopic != topicDiscovery.selectedTopic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<TopicDiscoveryProvider>().synchronizeSelectedTopic(
            targetTopic,
          );
        }
      });
    }

    // Don't touch the URL while another page (settings, memory, …) is
    // pushed on top of the chat.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final targetLocation = currentId == null || conv?.isPrimary == true
        ? '/chat'
        : '/chat/$currentId';
    final currentLocation = widget.conversationId == null
        ? '/chat'
        : '/chat/${widget.conversationId}';
    if (targetLocation == currentLocation) return;
    GoRouter.of(context).go(targetLocation);
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

  /// Transcript downloads for both threads and rooms (see the sidebar menus).
  final TranscriptExportService _transcriptExport = TranscriptExportService();

  /// Smart auto-scroll (streaming follow with reader-friendly release,
  /// jump-to-bottom pill, keyboard follow) — shared with the rooms view.
  final SmartScrollController _scroll = SmartScrollController();
  ScrollController get _scrollController => _scroll.controller;
  Timer? _syncTimer;
  bool _visionWarningScheduled = false;
  bool _visionWarningOpen = false;
  bool _showActiveContext = true;

  // Smart auto-scroll: follow new content only when the user is already
  // reading the latest messages; never yank them away from scrollback.
  ChatProvider? _chatProviderRef;
  final ReadAloudAutoPlayTracker _autoPlayTracker = ReadAloudAutoPlayTracker();

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
      _chatProviderRef?.removeListener(_onChatStateChanged);
      _chatProviderRef = provider;
      provider.streamingMessage.addListener(_onStreamingUpdate);
      _autoPlayTracker.reset(
        sending: provider.isSending,
        conversationId: provider.currentConversation?.id,
        messages: provider.messages,
      );
      provider.addListener(_onChatStateChanged);
    }
    _startSyncTimer();
  }

  @override
  void didUpdateWidget(covariant _ChatPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      final provider = _chatProviderRef;
      _autoPlayTracker.reset(
        sending: provider?.isSending ?? false,
        conversationId: provider?.currentConversation?.id,
        messages: provider?.messages ?? const [],
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _chatProviderRef?.streamingMessage.removeListener(_onStreamingUpdate);
    _chatProviderRef?.removeListener(_onChatStateChanged);
    _scrollController.removeListener(_maybeLoadOlderMessages);
    _scroll.dispose();
    super.dispose();
  }

  void _onChatStateChanged() {
    final provider = _chatProviderRef;
    if (provider == null || widget.roomId != null) return;
    final message = _autoPlayTracker.observe(
      sending: provider.isSending,
      conversationId: provider.currentConversation?.id,
      messages: provider.messages,
      hasError: provider.error != null,
    );
    if (message == null) return;
    final conversationId = provider.currentConversation?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.roomId != null) return;
      final chat = context.read<ChatProvider>();
      final settings = context.read<SettingsProvider>();
      if (chat.currentConversation?.id != conversationId ||
          chat.isSending ||
          !settings.autoPlayTts ||
          settings.talkModeActive ||
          !chat.messages.any((current) => current.id == message.id)) {
        return;
      }
      final listening = context.read<ReadAloudController>();
      if (listening.active && listening.messageId != message.id) return;
      unawaited(
        listening.start(
          messageId: message.id,
          text: readableReplyContent(message),
          voiceEn: settings.readAloudVoiceEn,
          voiceEs: settings.readAloudVoiceEs,
          speed: settings.ttsSpeed,
          languageMode: settings.readAloudLanguageMode,
        ),
      );
    });
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
    final chat = context.read<ChatProvider>();
    context.read<TopicDiscoveryProvider>().startNewTopic();
    context.go('/chat');
    unawaited(chat.enterPrimaryConversation());
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
        onRedirect: _newChat,
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
      onDownloadConversation: _downloadConversation,
      onDownloadRoom: _downloadRoom,
      initialTab: widget.roomId != null ? 1 : 0,
      selectedRoomId: widget.roomId,
      onSelectRoom: _selectRoom,
      onDeleteRoom: _deleteRoom,
    );
  }

  Future<void> _downloadConversation(Conversation conversation) =>
      downloadConversationTranscript(context, _transcriptExport, conversation);

  Future<void> _downloadRoom(Room room) =>
      downloadRoomTranscript(context, _transcriptExport, room);

  void _deleteWithUndo(ChatProvider chatProvider, String id) =>
      deleteConversationWithUndoSnack(context, chatProvider, id);

  void _snack(String msg, {bool error = false}) =>
      showChatSnack(context, msg, error: error);

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
    final topicDiscovery = context.watch<TopicDiscoveryProvider>();
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

    final isTopicConversation =
        chatProvider.currentConversation?.isPrimary == true ||
        chatProvider.currentConversation?.activeTopicId != null;
    final showTopicSurface =
        isTopicConversation &&
        (chatProvider.currentConversation?.isPrimary != true ||
            !topicDiscovery.showLanding);

    return PopScope(
      canPop: !panelOverlayOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) chatProvider.panel.close();
      },
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: const SettingsDrawer(),
        body: ChatDropZone(
          enabled: widget.roomId == null,
          onSnack: _snack,
          child: Stack(
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
                      onDownloadConversation: _downloadConversation,
                      onDownloadRoom: _downloadRoom,
                      isLoadingConversations:
                          chatProvider.isLoadingConversations,
                      selectedRoomId: widget.roomId,
                      initialTab: widget.roomId != null ? 1 : 0,
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
                            onNewChat: _newChat,
                          ),
                          if (chatProvider.error != null &&
                              chatProvider.errorType !=
                                  'unsupported_image_input')
                            ChatErrorBanner(
                              message: chatProvider.error!,
                              onDismiss: chatProvider.clearError,
                            ),
                          if (chatProvider.responseRecoveryState != null)
                            ResponseRecoveryNotice(
                              state: chatProvider.responseRecoveryState!,
                            ),
                          Builder(
                            builder: (_) {
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
                          if (showTopicSurface) const TopicBanner(),
                          Expanded(
                            child: Stack(
                              children: [
                                ChatTranscriptView(
                                  scrollController: _scrollController,
                                  streamAnchorKey: _scroll.streamAnchorKey,
                                  onOpenActiveContext: _openActiveContext,
                                  onStarterFromLanding: (message) async {
                                    await submitChatComposerMessage(
                                      chatProvider: chatProvider,
                                      topicDiscovery: topicDiscovery,
                                      message: message,
                                      attachments: const [],
                                    );
                                  },
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: _scroll.showJumpToBottom,
                                  builder: (context, show, _) => show
                                      ? Positioned(
                                          right: 16,
                                          bottom: 12,
                                          child: FloatingActionButton.small(
                                            heroTag: 'jump_to_bottom',
                                            tooltip: l10n.jumpToLatestMessage,
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
                          WorkflowCompletionNotice(
                            conversation: chatProvider.currentConversation,
                          ),
                          Consumer<ChatProvider>(
                            builder: (context, provider, _) {
                              return ChatInputWidget(
                                onFolderAttached: (id) async {
                                  if (chatProvider.currentConversation?.id ==
                                          id &&
                                      !chatProvider.isSending) {
                                    await chatProvider.loadConversation(id);
                                  }
                                },
                                ensureFolderConversation: () async {
                                  final discovery = context
                                      .read<TopicDiscoveryProvider>();
                                  var conversation =
                                      chatProvider.currentConversation;
                                  if (conversation == null ||
                                      (conversation.isPrimary &&
                                          discovery.showLanding)) {
                                    conversation = await chatProvider
                                        .createConversation();
                                    if (conversation == null) {
                                      throw StateError(
                                        chatProvider.error ??
                                            'Could not create conversation',
                                      );
                                    }
                                    discovery.conversationStarted();
                                  }
                                  return conversation.id;
                                },
                                onSend: (message, attachments) async {
                                  final merged = [...attachments];
                                  if (provider.pendingAttachments != null) {
                                    merged.addAll(provider.pendingAttachments!);
                                    provider.clearPendingAttachments();
                                  }
                                  await submitChatComposerMessage(
                                    chatProvider: provider,
                                    topicDiscovery: context
                                        .read<TopicDiscoveryProvider>(),
                                    message: message,
                                    attachments: merged,
                                  );
                                },
                                onStop:
                                    provider.canStopGeneration &&
                                        !topicDiscovery.startingTopic
                                    ? () => provider.stopStreaming()
                                    : null,
                                isLoading:
                                    chatProvider.isSending ||
                                    topicDiscovery.startingTopic,
                                initialAttachments: provider.pendingAttachments,
                                onOpenContext: isTopicConversation
                                    ? _openActiveContext
                                    : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  if (widget.roomId == null &&
                      showTopicSurface &&
                      _showActiveContext &&
                      context.isWide)
                    SizedBox(
                      width: 340,
                      child: ActiveContextPanel(
                        conversationId: chatProvider.currentConversation!.id,
                        onRedirect: _newChat,
                        onClose: () =>
                            setState(() => _showActiveContext = false),
                      ),
                    ),
                  if (chatProvider.panel.isOpen && context.isWide)
                    ResizableMicroAppPane(panel: chatProvider.panel),
                ],
              ),
              if (chatProvider.panel.isOpen && context.isNarrow)
                Positioned.fill(
                  child: MicroAppPanel(
                    panel: chatProvider.panel,
                    showCloseAsBack: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
