import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/core/error_reporter.dart';
import 'package:garbanzo_ai/features/microapps/providers/microapp_panel_controller.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/conversation_list_controller.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_stream_controller.dart';
import 'package:garbanzo_ai/features/chat/providers/client_folder_controller.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';

const _uuid = Uuid();

enum ChatResponseRecoveryState { waitingForConnection, syncing }

/// Provider for managing chat conversation and message state.
///
/// Model selection is handled by [ModelProvider]. The currently-selected
/// model id is pushed in via [selectedModelId] (wired through a
/// `ChangeNotifierProxyProvider` in the page) so the two stay decoupled.
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    String? selectedModelId,
    ChatService? chatService,
    FolderReader folderReader = const FolderReader(),
    Duration recoveryPollInterval = const Duration(seconds: 2),
  }) : _selectedModelIdValue = selectedModelId,
       _chatService = chatService ?? ChatService.instance,
       _recoveryPollInterval = recoveryPollInterval {
    conversationList = ConversationListController(chatService: _chatService);
    // Rebuild chat widgets when the micro-app panel opens/closes/reloads
    // or the sidebar list changes.
    panel.addListener(notifyListeners);
    conversationList.addListener(notifyListeners);
    conversationList.load();
    _folders = ClientFolderController(
      chatService: _chatService,
      onChanged: notifyListeners,
      folderReader: folderReader,
    );
    _folders.load();
  }

  final ChatService _chatService;
  final Duration _recoveryPollInterval;
  late final ClientFolderController _folders;

  /// Sidebar conversation list (loading, pin, optimistic delete + undo).
  /// Notifications are forwarded, so watching this provider is enough.
  late final ConversationListController conversationList;
  String? _selectedModelIdValue;

  /// Latest model selection from [ModelProvider]; updated by the
  /// ProxyProvider without rebuilding this provider. No notify — selection
  /// only affects *future* sends/creates, not currently-rendered state.
  set selectedModelId(String? id) => _selectedModelIdValue = id;

  String? _selectedModelId() => _selectedModelIdValue;

  ThinkingLevel? _pendingThinkingLevelValue;

  /// Thinking level composed in the style picker for the *next* new
  /// conversation; pushed in from [StyleProvider] by the ProxyProvider (same
  /// pattern as [selectedModelId]). No notify — it only affects future
  /// creates.
  set pendingThinkingLevel(ThinkingLevel? level) =>
      _pendingThinkingLevelValue = level;

  String? _pendingSystemPromptValue;

  /// System prompt (resolved template content) for the *next* new
  /// conversation; pushed in from [StyleProvider] like [selectedModelId].
  set pendingSystemPrompt(String? prompt) => _pendingSystemPromptValue = prompt;

  /// Drives the live micro-app panel beside the chat. Opened when the model
  /// calls the `house_designer` tool (see the tool_result branch below) or by
  /// the manual 🏠 composer button.
  final MicroappPanelController panel = MicroappPanelController();

  // ==========================================================================
  // State
  // ==========================================================================

  Conversation? _currentConversation;
  Conversation? get currentConversation => _currentConversation;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  // Initial/reload window size (B-03): a full multi-hundred-message history
  // is slow to transfer and parse, so only this many recent messages are
  // fetched up front. Older ones page in on demand via loadOlderMessages.
  static const int _messageWindow = 60;

  // Backend cap on GET /conversations/{id}?message_limit= (le=500); asking
  // for more is a validation error, not a bigger window.
  static const int _maxMessageLimit = 500;

  /// Whether older messages exist beyond what's currently loaded.
  bool get hasMoreMessages => _currentConversation?.hasMoreMessages ?? false;

  bool _loadingOlderMessages = false;
  bool get loadingOlderMessages => _loadingOlderMessages;

  bool _isSending = false;
  bool get isSending => _isSending || isRecoveringResponse;

  ChatResponseRecoveryState? _responseRecoveryState;
  ChatResponseRecoveryState? get responseRecoveryState =>
      _responseRecoveryState;
  bool get isRecoveringResponse => _responseRecoveryState != null;
  Timer? _responseRecoveryTimer;
  String? _recoveryConversationId;
  Set<String> _assistantIdsBeforeRecovery = const {};

  List<Conversation> get conversations => conversationList.conversations;

  bool get isLoadingConversations => conversationList.isLoading;

  String? _error;
  String? get error => _error ?? conversationList.error;

  Map<String, dynamic>? _errorMetadata;
  String? get errorType =>
      _error == null ? null : _errorMetadata?['error_type'] as String?;

  final ChatStreamController _stream = ChatStreamController();

  // ==========================================================================
  // Streaming message channel
  // ==========================================================================
  //
  // Per-chunk content updates go through this ValueNotifier instead of
  // notifyListeners(), so only the streaming bubble rebuilds — not the whole
  // message list (which would also re-parse every visible message's
  // markdown). The list itself only changes on structural events: stream
  // start, tool calls/results, per-iteration done, and end of stream.

  /// Live view of the assistant message currently being streamed.
  ValueNotifier<ChatMessage?> get streamingMessage => _stream.streamingMessage;

  /// ID of the in-flight assistant placeholder, if a stream is active.
  String? get streamingMessageId => _stream.messageId;

  void _pushStreamingUpdate(ChatMessage message, {bool force = false}) {
    _stream.push(message, force: force);
  }

  /// Commit the latest streamed content into [_messages] before a structural
  /// change (tool insert, stop, end of stream), so list state never lags
  /// behind what the user already saw in the live bubble.
  void _syncStreamingIntoList() {
    _stream.sync(_upsertIntoList);
  }

  void _clearStreamingState() {
    _stream.clear();
  }

  // ==========================================================================
  // Conversations
  // ==========================================================================

  Future<void> refreshConversations() async => conversationList.load();

  bool _syncingFromServer = false;

  /// Reconcile idle chat state with changes made by another signed-in client.
  ///
  /// The sidebar refresh stays silent so foreground polling does not flash a
  /// loading state. An active local stream owns the message list and must not
  /// be replaced by a remote snapshot midway through generation.
  Future<void> syncFromServer() async {
    if (_syncingFromServer) return;
    _syncingFromServer = true;
    try {
      await Future.wait([
        conversationList.load(showLoading: false),
        if (!_isSending && !_stream.isActive) _reloadCurrentConversation(),
      ]);
    } finally {
      _syncingFromServer = false;
    }
  }

  Future<void> loadConversation(String conversationId) async {
    // Switching away mid-stream: stop the old stream so its chunks can't
    // bleed into the newly loaded conversation's message list.
    if (_stream.isActive && _currentConversation?.id != conversationId) {
      await stopStreaming();
    }

    _cancelResponseRecovery();
    _error = null;
    _errorMetadata = null;
    _actionEpoch++;
    notifyListeners();

    try {
      final conversation = await _chatService.getConversation(
        conversationId,
        messageLimit: _messageWindow,
      );
      _currentConversation = conversation;
      _messages = _hydrateAttachments(conversation.messages ?? []);
      _setErrorContext();
      // Loading an existing conversation discards any folder the user picked
      // on a new-chat composer — it belonged to the chat they were about to
      // start, not this one. (The create path adopts it instead.)
      unawaited(_folders.clear(null));
    } catch (e) {
      _errorMetadata = null;
      _error = 'Failed to load conversation: $e';
      logDebug(_error!);
    } finally {
      notifyListeners();
    }
  }

  /// Pages in messages older than the oldest one currently loaded (B-03),
  /// e.g. triggered when the user scrolls to the top of the message list.
  Future<void> loadOlderMessages() async {
    final conversation = _currentConversation;
    if (conversation == null ||
        !conversation.hasMoreMessages ||
        _loadingOlderMessages ||
        _messages.isEmpty) {
      return;
    }

    _loadingOlderMessages = true;
    notifyListeners();

    final oldestId = _messages.first.id;
    try {
      final (older, hasMore) = await _chatService.getOlderMessages(
        conversation.id,
        oldestId,
      );
      if (_currentConversation?.id == conversation.id) {
        _messages = [..._hydrateAttachments(older), ..._messages];
        _currentConversation = conversation.copyWith(hasMoreMessages: hasMore);
      }
    } catch (e) {
      logDebug('Failed to load older messages: $e');
    } finally {
      _loadingOlderMessages = false;
      notifyListeners();
    }
  }

  Future<void> createConversation({
    String? title,
    String? model,
    String? initialMessage,
    String? systemPrompt,
    ThinkingLevel? thinkingLevel,
    List<ChatAttachment> initialAttachments = const [],
  }) async {
    _error = null;
    _errorMetadata = null;
    notifyListeners();

    try {
      final selectedModel = model ?? _selectedModelId() ?? 'llama3.2';
      final derivedTitle =
          title ??
          (initialMessage != null && initialMessage.isNotEmpty
              ? initialMessage.substring(
                  0,
                  initialMessage.length > 50 ? 50 : initialMessage.length,
                )
              : null);
      final conversation = await _chatService.createConversation(
        title: derivedTitle,
        model: selectedModel,
        systemPrompt: systemPrompt ?? _pendingSystemPromptValue,
        thinkingLevel: thinkingLevel ?? _pendingThinkingLevelValue,
      );

      _currentConversation = conversation;
      _messages = [];
      _setErrorContext();

      // A folder the user attached on the empty "new chat" state keys onto
      // the real conversation id now that it exists, so the first send
      // carries `has_client_folder=true` and the chip keeps showing.
      await _folders.adoptPending(conversation.id);

      // Immediately add the new conversation to the list for sidebar visibility
      conversationList.prepend(conversation.copyWith(messageCount: 0));
      notifyListeners();

      if (initialMessage != null && initialMessage.isNotEmpty) {
        await sendMessage(initialMessage, attachments: initialAttachments);
      } else {
        notifyListeners();
      }

      await conversationList.load();
    } catch (e) {
      _errorMetadata = null;
      _error = 'Failed to create conversation: $e';
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  Future<void> updateConversation({
    String? title,
    String? model,
    bool? useMemory,
    bool? useKnowledgeBase,
    String? systemPrompt,
    bool clearSystemPrompt = false,
    List<String>? enabledTools,
    bool clearEnabledTools = false,
    bool? isPinned,
    ThinkingLevel? thinkingLevel,
    bool setThinkingLevel = false,
  }) async {
    if (_currentConversation == null) return;

    _error = null;
    _errorMetadata = null;
    notifyListeners();

    try {
      final updated = await _chatService.updateConversation(
        _currentConversation!.id,
        title: title,
        model: model,
        useMemory: useMemory,
        useKnowledgeBase: useKnowledgeBase,
        systemPrompt: systemPrompt,
        clearSystemPrompt: clearSystemPrompt,
        enabledTools: enabledTools,
        clearEnabledTools: clearEnabledTools,
        isPinned: isPinned,
        thinkingLevel: thinkingLevel,
        setThinkingLevel: setThinkingLevel,
      );
      _currentConversation = updated;
      await conversationList.load();
    } catch (e) {
      _errorMetadata = null;
      _error = 'Failed to update conversation: $e';
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Change only this conversation's model and retry its latest user turn.
  /// The backend edit path preserves attachment metadata, while the partial
  /// update leaves the conversation prompt, thinking level, and tools intact.
  /// Saved styles and new-chat defaults live in separate providers and are
  /// deliberately not changed here.
  Future<bool> switchModelAndRetryLastTurn(String modelId) async {
    final conversation = _currentConversation;
    if (conversation == null || isSending) return false;

    _error = null;
    _errorMetadata = null;
    _isSending = true;
    notifyListeners();

    try {
      await _stream.cancel();
      _syncStreamingIntoList();
      _clearStreamingState();

      await _chatService.updateConversation(conversation.id, model: modelId);
      final refreshed = await _chatService.getConversation(
        conversation.id,
        messageLimit: _messageWindow,
      );
      _currentConversation = refreshed;
      _messages = _hydrateAttachments(refreshed.messages ?? []);

      final userIndex = _messages.lastIndexWhere((message) => message.isUser);
      if (userIndex < 0) {
        throw StateError('No user message is available to retry');
      }
      final userMessage = _messages[userIndex];
      _isSending = false;
      await editUserMessage(
        userMessage.id,
        _editableUserContent(userMessage.content),
      );
      return true;
    } catch (e) {
      _isSending = false;
      _errorMetadata = null;
      _error = 'Failed to switch models and retry: $e';
      logDebug(_error!);
      notifyListeners();
      return false;
    }
  }

  Future<void> togglePin(String conversationId) async {
    final updated = await conversationList.togglePin(conversationId);
    if (updated != null && _currentConversation?.id == conversationId) {
      _currentConversation = updated;
      notifyListeners();
    }
  }

  /// Mute or unmute [conversationId]. [duration] is one of `8h`, `1w`,
  /// `forever`, `unmute`.
  Future<void> setMute(String conversationId, String duration) async {
    final updated = await conversationList.setMute(conversationId, duration);
    if (updated != null && _currentConversation?.id == conversationId) {
      _currentConversation = updated;
      notifyListeners();
    }
  }

  // ==========================================================================
  // Client-side folder attachment (idea 17)
  //
  // The attached folder lives ONLY on this client — never sent to the backend.
  // When a folder is attached, sends set has_client_folder=true so the agent
  // gets read_file/list_files; the backend delegates each read back here via a
  // client_tool_request chunk, which [ClientFolderController] fulfils locally.
  // ==========================================================================

  String? clientFolderFor(String? conversationId) =>
      _folders.folderFor(conversationId);

  String? clientFolderNameFor(String? conversationId) =>
      _folders.folderNameFor(conversationId);

  Future<void> attachClientFolder(String? conversationId, String path) =>
      _folders.attach(conversationId, path);

  Future<void> clearClientFolder(String? conversationId) =>
      _folders.clear(conversationId);

  Future<void> deleteConversation(String conversationId) async {
    _error = null;
    _errorMetadata = null;
    _actionEpoch++;

    if (_currentConversation?.id == conversationId) {
      _currentConversation = null;
      _messages = [];
      notifyListeners();
    }
    conversationList.delete(conversationId);
  }

  /// Restore a conversation deleted within the undo window.
  void undoDeleteConversation(String conversationId) =>
      conversationList.undoDelete(conversationId);

  void clearCurrentConversation() {
    if (_stream.isActive) {
      unawaited(stopStreaming());
    }
    _currentConversation = null;
    _messages = [];
    _cancelResponseRecovery();
    _error = null;
    _errorMetadata = null;
    _actionEpoch++;
    notifyListeners();
  }

  bool get hasActiveConversation => _currentConversation != null;

  /// Add attachments to the current message being composed.
  /// Called when files are dragged onto the chat area.
  void addAttachments(List<ChatAttachment> attachments) {
    // For now, we just store them in a temporary holder.
    // The attachments will be sent with the next message.
    // This mirrors the file picker behavior in ChatInputWidget.
    _pendingAttachments ??= [];
    _pendingAttachments!.addAll(attachments);
    notifyListeners();
  }

  List<ChatAttachment>? _pendingAttachments;
  List<ChatAttachment>? get pendingAttachments => _pendingAttachments;

  void clearPendingAttachments() {
    _pendingAttachments = null;
    notifyListeners();
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  /// Updates the current conversation's entry in the conversations list.
  void _updateConversationInList() {
    final current = _currentConversation;
    if (current != null) conversationList.replaceEntry(current);
  }

  // ==========================================================================
  // Messaging
  // ==========================================================================

  Future<void> sendMessage(
    String content, {
    List<ChatAttachment> attachments = const [],
    String? talkModeInstruction,
  }) async {
    if (content.trim().isEmpty && attachments.isEmpty) return;

    // Guard: prevent sending while already streaming.
    if (isSending) return;

    _error = null;
    _errorMetadata = null;
    _actionEpoch++;

    if (_currentConversation == null) {
      await createConversation(
        model: _selectedModelId() ?? 'llama3.2',
        initialMessage: content,
        initialAttachments: attachments,
      );
      return;
    }

    _isSending = true;

    final userMessage = ChatMessage(
      id: 'temp-${_uuid.v4()}',
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
      attachments: attachments,
    );
    _messages = [..._messages, userMessage];
    _setErrorContext(messageId: userMessage.id);

    // Update current conversation with new message count for sidebar
    if (_currentConversation != null) {
      _currentConversation = _currentConversation!.copyWith(
        messageCount: _messages.length,
      );
      _updateConversationInList();
    }
    notifyListeners();

    try {
      final stream = _chatService.streamChatResponse(
        _currentConversation!.id,
        content,
        attachments: attachments,
        hasClientFolder: _folders.hasFolder(_currentConversation!.id),
        clientFolderLabel: clientFolderNameFor(_currentConversation!.id),
        talkModeInstruction: talkModeInstruction,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _errorMetadata = null;
      _error = _friendlyStreamError(e);
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Regenerate the last assistant reply in the current conversation.
  Future<void> regenerateLastAssistant() async {
    if (_currentConversation == null || isSending) return;

    final lastAssistantIdx = _messages.lastIndexWhere(
      (m) => m.isAssistant && !m.id.startsWith('temp-'),
    );
    if (lastAssistantIdx < 0) return;
    final messageId = _messages[lastAssistantIdx].id;

    _error = null;
    _errorMetadata = null;
    _actionEpoch++;
    _isSending = true;
    // Trim the old assistant reply and any trailing tool turns we've already
    // rendered locally; the backend does the same deletion for us.
    _messages = _messages.sublist(0, lastAssistantIdx);
    notifyListeners();

    try {
      final stream = _chatService.regenerateMessage(
        _currentConversation!.id,
        messageId,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _errorMetadata = null;
      _error = _friendlyStreamError(e);
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Edit a user message's text and re-run the conversation from that point.
  Future<void> editUserMessage(String messageId, String newContent) async {
    if (_currentConversation == null || isSending) return;
    if (newContent.trim().isEmpty) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final target = _messages[idx];
    if (!target.isUser) return;

    _error = null;
    _errorMetadata = null;
    _actionEpoch++;
    _isSending = true;

    // Optimistically update the message text and drop everything after it.
    final edited = target.copyWith(content: newContent);
    _messages = [..._messages.sublist(0, idx), edited];
    notifyListeners();

    try {
      final stream = _chatService.editMessage(
        _currentConversation!.id,
        messageId,
        newContent,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _errorMetadata = null;
      _error = _friendlyStreamError(e);
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Fork the conversation from a specific message into a new branch.
  Future<void> branchFromMessage(String messageId) async {
    if (_currentConversation == null) return;

    _error = null;
    _errorMetadata = null;
    notifyListeners();

    try {
      final newConv = await _chatService.branchConversation(
        _currentConversation!.id,
        messageId,
      );
      // Prepend to sidebar list
      conversationList.prepend(newConv);
      // Navigate to new branch
      await loadConversation(newConv.id);
    } catch (e) {
      _errorMetadata = null;
      _error = 'Failed to branch conversation: $e';
      logDebug(_error!);
      notifyListeners();
    }
  }

  void _consumeAssistantStream(Stream<ChatResponseChunk> stream) {
    final assistantMessageId = 'temp-${_uuid.v4()}';
    // The conversation this stream belongs to, captured so a client_tool_request
    // is served against the right folder even if the user navigates away.
    final streamConversationId = _currentConversation?.id;
    ErrorReporter.instance.setContext(
      conversationId: streamConversationId,
      context: {'surface': 'chat'},
    );
    var accumulatedContent = '';
    var accumulatedThinking = '';

    ChatMessage current([Map<String, dynamic>? doneMetadata]) =>
        _buildAssistantMessage(
          assistantMessageId,
          accumulatedContent,
          accumulatedThinking,
          doneMetadata,
        );

    // Single assistant placeholder, anchored at the END of the message list
    // throughout the stream. Tool calls / tool results get inserted BEFORE
    // it as they arrive, mirroring the canonical layout the server sends
    // back on reload — so there's no jarring "two placeholders merge into
    // one" jolt when the stream finishes. Thinking from tool-calling
    // iterations accumulates onto the same placeholder; the backend
    // persists it the same way.
    //
    // Per-chunk content flows through [streamingMessage] only; the list
    // (and notifyListeners) is reserved for structural changes.
    _upsertIntoList(current());
    _pushStreamingUpdate(current(), force: true);
    notifyListeners();

    _stream.listen(
      stream,
      messageId: assistantMessageId,
      onChunk: (chunk) {
        if (chunk.isThinking && chunk.content != null) {
          accumulatedThinking += chunk.content!;
          _pushStreamingUpdate(current());
        } else if (chunk.isChunk && chunk.content != null) {
          accumulatedContent += chunk.content!;
          _pushStreamingUpdate(current());
        } else if (chunk.isToolCall) {
          _syncStreamingIntoList();
          _insertToolCallMessagesBefore(
            assistantMessageId,
            chunk.toolCalls ?? const [],
          );
          notifyListeners();
        } else if (chunk.isToolResult) {
          _syncStreamingIntoList();
          _insertToolResultMessageBefore(assistantMessageId, chunk.toolResult);
          // A house_designer result carries a panel signal — reveal/refresh
          // the live micro-app view next to the chat.
          final tr = chunk.toolResult;
          if (tr != null) {
            panel.openFromToolResult(tr.toolName, tr.result);
          }
          notifyListeners();
        } else if (chunk.isToolExecution) {
          // Live tool status (started / finished + duration): merge it into
          // the matching tool_call message so its bubble re-renders.
          _applyToolExecution(chunk.toolExecution);
        } else if (chunk.isClientToolRequest) {
          // The backend is asking us to read a file from the attached folder
          // (idea 17). Serve it locally without blocking the stream.
          final request = chunk.clientToolRequest;
          if (streamConversationId != null && request != null) {
            unawaited(_folders.serveToolRequest(streamConversationId, request));
          }
        } else if (chunk.isDone) {
          // The backend emits a `done` chunk PER LLM ITERATION (one for the
          // tool-call iteration, one for the final-answer iteration). It is
          // NOT the end-of-stream marker — that's the SSE stream's own
          // onDone callback. So here we only commit metadata to whatever
          // assistant message has been accumulating; we do NOT flip
          // _isSending or reload (a reload mid-stream would replace
          // _messages with the partial server state and erase everything we
          // just streamed).
          if (accumulatedContent.isNotEmpty || accumulatedThinking.isNotEmpty) {
            final committed = current(chunk.metadata);
            _upsertIntoList(committed);
            _pushStreamingUpdate(committed, force: true);
            notifyListeners();
          }
        } else if (chunk.isError) {
          _syncStreamingIntoList();
          _error = chunk.error ?? 'An error occurred';
          _errorMetadata = chunk.metadata;
          _isSending = false;
          notifyListeners();
        }
      },
      onError: (e) {
        _syncStreamingIntoList();
        _isSending = false;
        logDebug('Stream error: $e');
        _clearStreamingState();
        if (_isConnectionError(e)) {
          _error = null;
          _errorMetadata = null;
          _beginResponseRecovery();
        } else {
          _errorMetadata = null;
          _error = _friendlyStreamError(e);
        }
        notifyListeners();
        if (!_isConnectionError(e)) _reloadCurrentConversation();
      },
      onDone: () {
        // Real end of the SSE stream — finalize and reconcile with server.
        _isSending = false;
        _syncStreamingIntoList();
        _clearStreamingState();
        if (accumulatedContent.isEmpty && accumulatedThinking.isEmpty) {
          // Drop the trailing empty placeholder if iteration N+1 never
          // produced anything (e.g., turn ended right after a tool call).
          _removeMessage(assistantMessageId);
        }
        if (_currentConversation != null) {
          _currentConversation = _currentConversation!.copyWith(
            messageCount: _messages.length,
          );
          _updateConversationInList();
        }
        notifyListeners();
        _reloadCurrentConversation();
        _scheduleTitleRefresh();
      },
    );
  }

  void _removeMessage(String id) {
    final filtered = _messages.where((m) => m.id != id).toList();
    if (filtered.length != _messages.length) {
      _messages = filtered;
    }
  }

  void _setErrorContext({String? messageId}) {
    ErrorReporter.instance.setContext(
      conversationId: _currentConversation?.id,
      messageId: messageId,
      context: {'surface': 'chat'},
    );
  }

  /// Translate a stream error into a short, user-facing English message.
  /// Raw [DioException]s and [Exception] strings like
  /// "Exception: Chat failed: 503 - ..." are replaced with friendly text;
  /// [ChatException] carries a machine-readable kind that maps directly.
  /// Localized at the widget layer where a context is available.
  String _friendlyStreamError(Object e) {
    if (e is ChatException) {
      return switch (e.kind) {
        'connection' =>
          'Couldn\'t reach the AI service. Check your connection and try again.',
        'unavailable' =>
          'The AI service is temporarily unavailable. Please try again in a moment.',
        'server' => 'The server encountered an error. Please try again.',
        _ => e.detail != null ? 'Chat error: ${e.detail}' : 'Chat error.',
      };
    }
    final s = '$e'.toLowerCase();
    if (s.contains('connection closed') ||
        s.contains('connection error') ||
        s.contains('connection refused') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('software caused connection abort')) {
      return 'Couldn\'t reach the AI service. Check your connection and try again.';
    }
    return 'Streaming error: $e';
  }

  bool _isConnectionError(Object error) {
    if (error is ChatException) return error.kind == 'connection';
    final text = '$error'.toLowerCase();
    return text.contains('connection closed') ||
        text.contains('connection error') ||
        text.contains('connection refused') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('software caused connection abort');
  }

  void _beginResponseRecovery() {
    final conversationId = _currentConversation?.id;
    if (conversationId == null) return;
    _responseRecoveryTimer?.cancel();
    _recoveryConversationId = conversationId;
    _assistantIdsBeforeRecovery = {
      for (final message in _messages)
        if (message.isAssistant && !message.id.startsWith('temp-')) message.id,
    };
    _responseRecoveryState = ChatResponseRecoveryState.waitingForConnection;
    _scheduleResponseRecovery(Duration.zero);
  }

  void _scheduleResponseRecovery(Duration delay) {
    _responseRecoveryTimer?.cancel();
    _responseRecoveryTimer = Timer(delay, () => unawaited(_recoverResponse()));
  }

  Future<void> _recoverResponse() async {
    if (!isRecoveringResponse ||
        _currentConversation?.id != _recoveryConversationId) {
      return;
    }
    final reachedServer = await _reloadCurrentConversation();
    if (!isRecoveringResponse) return;
    if (reachedServer &&
        _responseRecoveryState != ChatResponseRecoveryState.syncing) {
      _responseRecoveryState = ChatResponseRecoveryState.syncing;
      notifyListeners();
    }
    _scheduleResponseRecovery(_recoveryPollInterval);
  }

  void _completeRecoveryIfResponseArrived() {
    if (!isRecoveringResponse ||
        _currentConversation?.id != _recoveryConversationId) {
      return;
    }
    final hasNewAssistant = _messages.any(
      (message) =>
          message.isAssistant &&
          !message.id.startsWith('temp-') &&
          !_assistantIdsBeforeRecovery.contains(message.id),
    );
    if (hasNewAssistant) _cancelResponseRecovery();
  }

  void _cancelResponseRecovery() {
    _responseRecoveryTimer?.cancel();
    _responseRecoveryTimer = null;
    _responseRecoveryState = null;
    _recoveryConversationId = null;
    _assistantIdsBeforeRecovery = const {};
  }

  Future<void> stopStreaming() async {
    unawaited(_stream.cancel());
    _isSending = false;
    _cancelResponseRecovery();
    _actionEpoch++;
    // Keep what was already streamed, marked as interrupted so the partial
    // answer isn't mistaken for a complete one.
    final pending = streamingMessage.value;
    if (pending != null && pending.id == streamingMessageId) {
      _upsertIntoList(
        pending.copyWith(metadata: {...?pending.metadata, 'stopped': true}),
      );
    }
    _clearStreamingState();
    notifyListeners();

    if (_currentConversation != null) {
      try {
        await _chatService.stopStreaming(_currentConversation!.id);
      } catch (e) {
        logDebug('Failed to stop streaming on backend: $e');
      }
    }
  }

  ChatMessage _buildAssistantMessage(
    String id,
    String content,
    String thinking,
    Map<String, dynamic>? doneMetadata,
  ) {
    final meta = <String, dynamic>{
      if (thinking.isNotEmpty) 'thinking': thinking,
      ...?doneMetadata,
    };

    return ChatMessage(
      id: id,
      role: 'assistant',
      content: content,
      createdAt: DateTime.now(),
      metadata: meta.isEmpty ? null : meta,
    );
  }

  void _upsertIntoList(ChatMessage message) {
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      final newMessages = List<ChatMessage>.from(_messages);
      newMessages[existingIndex] = message;
      _messages = newMessages;
    } else {
      _messages = [..._messages, message];
    }
  }

  /// Inserts display-only `tool_call` messages for each call streamed,
  /// placed immediately BEFORE the assistant placeholder so the placeholder
  /// stays anchored at the end of the conversation.
  void _insertToolCallMessagesBefore(String anchorId, List<ToolCall> calls) {
    if (calls.isEmpty) return;
    final additions = <ChatMessage>[];
    for (final call in calls) {
      additions.add(
        ChatMessage(
          id: 'temp-tool-call-${call.id}',
          role: 'tool_call',
          content: call.name,
          createdAt: DateTime.now(),
          metadata: {
            'tool_calls': [
              {
                'id': call.id,
                'name': call.name,
                'arguments': call.arguments ?? const {},
              },
            ],
          },
        ),
      );
    }
    final idx = _messages.indexWhere((m) => m.id == anchorId);
    if (idx < 0) {
      _messages = [..._messages, ...additions];
      return;
    }
    _messages = [
      ..._messages.sublist(0, idx),
      ...additions,
      ..._messages.sublist(idx),
    ];
  }

  /// Merge a live tool-execution status update into the matching temp
  /// tool_call message's metadata, so its bubble can show "running…" /
  /// "done in X.Xs" while the rest of the list stays untouched.
  void _applyToolExecution(Map<String, dynamic>? execution) {
    final callId = execution?['tool_call_id'];
    if (execution == null || callId == null) return;
    final idx = _messages.indexWhere((m) => m.id == 'temp-tool-call-$callId');
    if (idx < 0) return;
    final message = _messages[idx];
    _upsertIntoList(
      message.copyWith(
        metadata: {...?message.metadata, 'tool_execution': execution},
      ),
    );
    notifyListeners();
  }

  /// Inserts a display-only `tool_result` message immediately BEFORE the
  /// assistant placeholder, mirroring the canonical layout the server
  /// returns on reload.
  void _insertToolResultMessageBefore(String anchorId, ToolResult? result) {
    if (result == null) return;
    final newMsg = ChatMessage(
      id: 'temp-tool-result-${result.toolCallId}',
      role: 'tool_result',
      content: result.toolName,
      createdAt: DateTime.now(),
      metadata: {
        'tool_result': {
          'tool_call_id': result.toolCallId,
          'tool_name': result.toolName,
          'result': result.result,
        },
      },
    );
    final idx = _messages.indexWhere((m) => m.id == anchorId);
    if (idx < 0) {
      _messages = [..._messages, newMsg];
      return;
    }
    _messages = [
      ..._messages.sublist(0, idx),
      newMsg,
      ..._messages.sublist(idx),
    ];
  }

  /// Bumped on every user action that changes message state (send, edit,
  /// regenerate, stop, switch). In-flight reloads compare epochs and drop
  /// their result if a newer action happened — otherwise the post-stream
  /// server reload could clobber an optimistic edit made while it was
  /// in flight.
  int _actionEpoch = 0;

  Future<bool> _reloadCurrentConversation() async {
    final id = _currentConversation?.id;
    if (id == null) return false;
    final epoch = _actionEpoch;
    try {
      // Request at least as many messages as are already displayed (which
      // grows if the user paged older ones in via loadOlderMessages) so this
      // reload — which runs after every single turn — never truncates
      // already-visible history back down to the initial window (B-03).
      // Past the backend's message_limit cap, fall back to the full history
      // (null) — a capped value would 422, silently breaking every reload.
      final needed = _messages.length < _messageWindow
          ? _messageWindow
          : _messages.length;
      final conversation = await _chatService.getConversation(
        id,
        messageLimit: needed > _maxMessageLimit ? null : needed,
        // Silent: this runs on background sync ticks and after every turn.
        // Transient 5xx shouldn't fire user-facing error reports.
        silent: true,
      );
      if (epoch != _actionEpoch || _currentConversation?.id != id) {
        return false; // stale — a newer action owns the state now
      }
      _currentConversation = conversation;
      _messages = _hydrateAttachments(conversation.messages ?? []);
      _completeRecoveryIfResponseArrived();
      notifyListeners();
      return true;
    } catch (e) {
      logDebug('Failed to reload conversation: $e');
      return false;
    }
  }

  // The backend auto-titles a conversation in the background after its
  // first exchange; refresh shortly after the stream ends so the generated
  // title replaces the raw-first-message placeholder in the sidebar.
  Timer? _titleRefreshTimer;

  void _scheduleTitleRefresh() {
    _titleRefreshTimer?.cancel();
    _titleRefreshTimer = Timer(const Duration(seconds: 4), () async {
      if (_isSending) return;
      await conversationList.load();
      final id = _currentConversation?.id;
      if (id == null) return;
      final list = conversationList.conversations;
      final idx = list.indexWhere((c) => c.id == id);
      if (idx >= 0 && list[idx].title != _currentConversation!.title) {
        _currentConversation = _currentConversation!.copyWith(
          title: list[idx].title,
        );
        notifyListeners();
      }
    });
  }

  // ==========================================================================
  // Attachment hydration
  // ==========================================================================

  /// Restore [ChatAttachment] objects from the metadata stored by the backend.
  List<ChatMessage> _hydrateAttachments(List<ChatMessage> messages) {
    return messages.map((msg) {
      final raw = msg.metadata?['attachments'];
      if (raw is! List || raw.isEmpty) return msg;

      final attachments = raw
          .whereType<Map<String, dynamic>>()
          .map((a) => ChatAttachment.fromMetadata(a))
          .toList();

      return msg.copyWith(attachments: attachments);
    }).toList();
  }

  String _editableUserContent(String content) {
    const marker = '\n\n[Attached file: ';
    final markerIndex = content.indexOf(marker);
    return markerIndex < 0 ? content : content.substring(0, markerIndex);
  }

  // ==========================================================================
  // Error handling
  // ==========================================================================

  void clearError() {
    _error = null;
    _errorMetadata = null;
    if (conversationList.error != null) {
      conversationList.clearError();
    }
    notifyListeners();
  }

  // ==========================================================================
  // Cleanup
  // ==========================================================================

  @override
  void dispose() {
    _stream.dispose();
    _responseRecoveryTimer?.cancel();
    _titleRefreshTimer?.cancel();
    panel.dispose();
    // Flushes pending undo-window deletions.
    conversationList.dispose();
    super.dispose();
  }
}
