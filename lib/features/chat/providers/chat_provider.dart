import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/microapps/providers/microapp_panel_controller.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/conversation_list_controller.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';

const _uuid = Uuid();

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
  }) : _selectedModelIdValue = selectedModelId,
       _chatService = chatService ?? ChatService.instance,
       _folderReader = folderReader {
    conversationList = ConversationListController(chatService: _chatService);
    // Rebuild chat widgets when the micro-app panel opens/closes/reloads
    // or the sidebar list changes.
    panel.addListener(notifyListeners);
    conversationList.addListener(notifyListeners);
    conversationList.load();
    _loadClientFolders();
  }

  final ChatService _chatService;

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
  bool get isSending => _isSending;

  List<Conversation> get conversations => conversationList.conversations;

  bool get isLoadingConversations => conversationList.isLoading;

  String? _error;
  String? get error => _error ?? conversationList.error;

  StreamSubscription<ChatResponseChunk>? _streamSubscription;

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
  final ValueNotifier<ChatMessage?> streamingMessage = ValueNotifier(null);

  /// ID of the in-flight assistant placeholder, if a stream is active.
  String? get streamingMessageId => _streamingMessageId;
  String? _streamingMessageId;

  // Notifier pushes are throttled: token chunks can arrive 50–100×/s and
  // each push re-parses the growing message's markdown. ~12 updates/s is
  // visually indistinguishable for streaming text at a fraction of the cost.
  static const _streamPushInterval = Duration(milliseconds: 80);
  DateTime _lastStreamPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamFlushTimer;
  ChatMessage? _pendingStreamMessage;

  void _pushStreamingUpdate(ChatMessage message, {bool force = false}) {
    _pendingStreamMessage = message;
    final now = DateTime.now();
    if (force || now.difference(_lastStreamPush) >= _streamPushInterval) {
      _streamFlushTimer?.cancel();
      _streamFlushTimer = null;
      _lastStreamPush = now;
      streamingMessage.value = message;
    } else {
      _streamFlushTimer ??= Timer(_streamPushInterval, () {
        _streamFlushTimer = null;
        _lastStreamPush = DateTime.now();
        final pending = _pendingStreamMessage;
        if (pending != null && pending.id == _streamingMessageId) {
          streamingMessage.value = pending;
        }
      });
    }
  }

  /// Commit the latest streamed content into [_messages] before a structural
  /// change (tool insert, stop, end of stream), so list state never lags
  /// behind what the user already saw in the live bubble.
  void _syncStreamingIntoList() {
    final pending = _pendingStreamMessage ?? streamingMessage.value;
    if (pending != null && pending.id == _streamingMessageId) {
      _upsertIntoList(pending);
    }
  }

  void _clearStreamingState() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _pendingStreamMessage = null;
    _streamingMessageId = null;
    streamingMessage.value = null;
  }

  // ==========================================================================
  // Conversations
  // ==========================================================================

  Future<void> refreshConversations() async => conversationList.load();

  Future<void> loadConversation(String conversationId) async {
    // Switching away mid-stream: stop the old stream so its chunks can't
    // bleed into the newly loaded conversation's message list.
    if (_streamSubscription != null &&
        _currentConversation?.id != conversationId) {
      await stopStreaming();
    }

    _error = null;
    _actionEpoch++;
    notifyListeners();

    try {
      final conversation = await _chatService.getConversation(
        conversationId,
        messageLimit: _messageWindow,
      );
      _currentConversation = conversation;
      _messages = _hydrateAttachments(conversation.messages ?? []);
    } catch (e) {
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
      _error = 'Failed to update conversation: $e';
      logDebug(_error!);
      notifyListeners();
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
  // client_tool_request chunk, which _serveClientToolRequest fulfils locally.
  // ==========================================================================

  final FolderReader _folderReader;
  final Map<String, String> _clientFolders = {};
  static const String _clientFoldersPrefsKey = 'client_folders';

  /// Absolute path of the folder attached to [conversationId], or null.
  String? clientFolderFor(String? conversationId) =>
      conversationId == null ? null : _clientFolders[conversationId];

  /// The attached folder's display name (base name), or null if none.
  ///
  /// Only the name is ever sent to the backend — never the path, which stays
  /// on this device (idea 17).
  String? clientFolderNameFor(String? conversationId) {
    final path = clientFolderFor(conversationId);
    if (path == null) return null;
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.last;
  }

  Future<void> _loadClientFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_clientFoldersPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _clientFolders
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k.toString(), v.toString())));
        notifyListeners();
      }
    } catch (e) {
      logDebug('Failed to load client folders: $e');
    }
  }

  Future<void> _persistClientFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clientFoldersPrefsKey, jsonEncode(_clientFolders));
    } catch (e) {
      logDebug('Failed to persist client folders: $e');
    }
  }

  /// Attach [path] to [conversationId] (desktop only). Local-only state.
  Future<void> attachClientFolder(String conversationId, String path) async {
    _clientFolders[conversationId] = path;
    notifyListeners();
    await _persistClientFolders();
  }

  /// Detach the folder from [conversationId].
  Future<void> clearClientFolder(String conversationId) async {
    if (_clientFolders.remove(conversationId) != null) {
      notifyListeners();
      await _persistClientFolders();
    }
  }

  /// Fulfil a backend `client_tool_request` by reading locally and posting the
  /// result. Runs async off the SSE consumer so it never blocks the stream.
  Future<void> _serveClientToolRequest(
    String conversationId,
    Map<String, dynamic> request,
  ) async {
    final toolCallId = request['tool_call_id']?.toString();
    final toolName = request['tool_name']?.toString();
    if (toolCallId == null) return;
    final root = _clientFolders[conversationId];
    final args = (request['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    final path = args['path']?.toString() ?? '';

    final payload = <String, dynamic>{'tool_call_id': toolCallId};
    try {
      if (root == null) {
        throw const FolderReadError('No folder is attached on this device.');
      }
      if (toolName == 'read_file') {
        final file = _folderReader.readFile(root, path);
        payload
          ..['ok'] = true
          ..['filename'] = file.filename
          ..['data'] = base64Encode(file.bytes);
      } else {
        payload
          ..['ok'] = true
          ..['entries'] = _folderReader.listDir(root, path);
      }
    } catch (e) {
      payload
        ..['ok'] = false
        ..['error'] = e is FolderReadError ? e.message : e.toString();
    }
    try {
      await _chatService.postClientToolResult(conversationId, payload);
    } catch (e) {
      logDebug('Failed to post client tool result: $e');
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    _error = null;
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
    if (_streamSubscription != null) {
      unawaited(stopStreaming());
    }
    _currentConversation = null;
    _messages = [];
    _error = null;
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
  }) async {
    if (content.trim().isEmpty && attachments.isEmpty) return;

    // Guard: prevent sending while already streaming.
    if (_isSending) return;

    _error = null;
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
        hasClientFolder: _clientFolders.containsKey(_currentConversation!.id),
        clientFolderLabel: clientFolderNameFor(_currentConversation!.id),
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _error = 'Failed to send message: $e';
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Regenerate the last assistant reply in the current conversation.
  Future<void> regenerateLastAssistant() async {
    if (_currentConversation == null || _isSending) return;

    final lastAssistantIdx = _messages.lastIndexWhere(
      (m) => m.isAssistant && !m.id.startsWith('temp-'),
    );
    if (lastAssistantIdx < 0) return;
    final messageId = _messages[lastAssistantIdx].id;

    _error = null;
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
      _error = 'Failed to regenerate: $e';
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Edit a user message's text and re-run the conversation from that point.
  Future<void> editUserMessage(String messageId, String newContent) async {
    if (_currentConversation == null || _isSending) return;
    if (newContent.trim().isEmpty) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final target = _messages[idx];
    if (!target.isUser) return;

    _error = null;
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
      _error = 'Failed to edit message: $e';
      _isSending = false;
      logDebug(_error!);
      notifyListeners();
    }
  }

  /// Fork the conversation from a specific message into a new branch.
  Future<void> branchFromMessage(String messageId) async {
    if (_currentConversation == null) return;

    _error = null;
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
    _streamingMessageId = assistantMessageId;
    _pushStreamingUpdate(current(), force: true);
    notifyListeners();

    _streamSubscription = stream.listen(
      (chunk) {
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
            unawaited(_serveClientToolRequest(streamConversationId, request));
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
          _isSending = false;
          notifyListeners();
        }
      },
      onError: (e) {
        _syncStreamingIntoList();
        _error = 'Streaming error: $e';
        _isSending = false;
        logDebug('Stream error: $e');
        _clearStreamingState();
        notifyListeners();
        // The connection can drop mid-generation (e.g. Android backgrounding
        // tears down the socket) after the backend already persisted a
        // partial or complete reply. Reload so that content replaces the
        // error instead of the reply looking lost, forcing a manual regenerate.
        _reloadCurrentConversation();
      },
      onDone: () {
        // Real end of the SSE stream — finalize and reconcile with server.
        _isSending = false;
        _streamSubscription = null;
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

  Future<void> stopStreaming() async {
    unawaited(_streamSubscription?.cancel());
    _streamSubscription = null;
    _isSending = false;
    _actionEpoch++;
    // Keep what was already streamed, marked as interrupted so the partial
    // answer isn't mistaken for a complete one.
    final pending = _pendingStreamMessage ?? streamingMessage.value;
    if (pending != null && pending.id == _streamingMessageId) {
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

  Future<void> _reloadCurrentConversation() async {
    final id = _currentConversation?.id;
    if (id == null) return;
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
      );
      if (epoch != _actionEpoch || _currentConversation?.id != id) {
        return; // stale — a newer action owns the state now
      }
      _currentConversation = conversation;
      _messages = _hydrateAttachments(conversation.messages ?? []);
      notifyListeners();
    } catch (e) {
      logDebug('Failed to reload conversation: $e');
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

  // ==========================================================================
  // Error handling
  // ==========================================================================

  void clearError() {
    _error = null;
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
    _streamSubscription?.cancel();
    _streamFlushTimer?.cancel();
    _titleRefreshTimer?.cancel();
    streamingMessage.dispose();
    panel.dispose();
    // Flushes pending undo-window deletions.
    conversationList.dispose();
    super.dispose();
  }
}
