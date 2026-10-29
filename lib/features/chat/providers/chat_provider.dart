import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:garbanzo_ai/core/error_reporter.dart';
import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/models/agent_liveness.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/chat/providers/agent_liveness_controller.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_message_list_helpers.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_response_recovery.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_stream_controller.dart';
import 'package:garbanzo_ai/features/chat/providers/client_folder_controller.dart';
import 'package:garbanzo_ai/features/chat/providers/conversation_list_controller.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';
import 'package:garbanzo_ai/features/microapps/providers/microapp_panel_controller.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';

export 'package:garbanzo_ai/features/chat/providers/chat_response_recovery.dart'
    show ChatResponseRecoveryState;

const _uuid = Uuid();

/// Provider for managing chat conversation and message state.
///
/// Model selection is handled by [ModelProvider]. The currently-selected
/// model id is pushed in via [selectedModelId] (wired through a
/// `ChangeNotifierProxyProvider`) so the two stay decoupled.
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    String? selectedModelId,
    ChatService? chatService,
    FolderReader folderReader = const FolderReader(),
    Duration recoveryPollInterval = const Duration(seconds: 2),
  }) : _selectedModelIdValue = selectedModelId,
       _chatService = chatService ?? ChatService.instance {
    conversationList = ConversationListController(chatService: _chatService);
    panel.addListener(_notifySafely);
    conversationList.addListener(_notifySafely);
    conversationList.load();
    _folders = ClientFolderController(
      chatService: _chatService,
      onChanged: _notifySafely,
      folderReader: folderReader,
    );
    _folders.load();
    _recovery = ChatResponseRecoveryController(
      pollInterval: recoveryPollInterval,
      currentConversationId: () => _currentConversation?.id,
      reloadCurrentConversation: _reloadCurrentConversation,
      onStateChanged: _notifySafely,
    );
  }

  final ChatService _chatService;
  late final ClientFolderController _folders;
  late final ChatResponseRecoveryController _recovery;
  late final ConversationListController conversationList;

  final MessageStarController _stars = MessageStarController();
  final ChatStreamController _stream = ChatStreamController();
  final AgentLivenessController _liveness = AgentLivenessController();
  final MicroappPanelController panel = MicroappPanelController();

  String? _selectedModelIdValue;
  set selectedModelId(String? id) => _selectedModelIdValue = id;
  String? _selectedModelId() => _selectedModelIdValue;

  ThinkingLevel? _pendingThinkingLevelValue;
  set pendingThinkingLevel(ThinkingLevel? level) =>
      _pendingThinkingLevelValue = level;

  String? _pendingSystemPromptValue;
  set pendingSystemPrompt(String? prompt) => _pendingSystemPromptValue = prompt;

  ValueChanged<Map<String, dynamic>>? onTopicUpdate;
  ValueChanged<Map<String, dynamic>>? onContextPreparing;
  ValueChanged<Map<String, dynamic>>? onContextUpdate;
  ValueChanged<Map<String, dynamic>>? onTopicDrift;
  VoidCallback? onConversationStarted;

  Conversation? _currentConversation;
  Conversation? get currentConversation => _currentConversation;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _disposed = false;
  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  bool isUpdatingMessageStar(String messageId) =>
      _stars.isUpdating(_currentConversation?.id, messageId);

  Future<bool> setMessageStar(String messageId, {required bool isStarred}) =>
      _stars.setStar(
        chatService: _chatService,
        conversation: _currentConversation,
        messages: _messages,
        messageId: messageId,
        isStarred: isStarred,
        isSending: isSending,
        isDisposed: () => _disposed,
        currentConversation: () => _currentConversation,
        onBeforeRequest: () {
          _clearError();
          _notifySafely();
        },
        onConfirmedVisible: (saved) {
          _messages = [
            for (final current in _messages)
              if (current.id == messageId)
                current.copyWith(isStarred: saved)
              else
                current,
          ];
          _currentConversation = _currentConversation!.copyWith(
            messages: _messages,
          );
        },
        onErrorVisible: (e) => _setError('Failed to update message star: $e'),
        onFinallyNotify: _notifySafely,
      );

  static const int _messageWindow = 60;
  static const int _maxMessageLimit = 500;

  bool get hasMoreMessages => _currentConversation?.hasMoreMessages ?? false;

  bool _loadingOlderMessages = false;
  bool get loadingOlderMessages => _loadingOlderMessages;

  bool _isSending = false;
  bool _isOpeningConversation = false;
  bool get isSending =>
      _isSending || isRecoveringResponse || _isOpeningConversation;
  bool get canStopGeneration =>
      !_isOpeningConversation && (_isSending || isRecoveringResponse);

  ChatResponseRecoveryState? get responseRecoveryState => _recovery.state;
  bool get isRecoveringResponse => _recovery.isRecovering;

  List<Conversation> get conversations => conversationList.conversations;
  bool get isLoadingConversations => conversationList.isLoading;

  String? _error;
  String? get error => _error ?? conversationList.error;

  Map<String, dynamic>? _errorMetadata;
  String? get errorType =>
      _error == null ? null : _errorMetadata?['error_type'] as String?;

  void _clearError() {
    _error = null;
    _errorMetadata = null;
  }

  void _setError(String msg, {Map<String, dynamic>? meta}) {
    _error = msg;
    _errorMetadata = meta;
    logDebug(msg);
  }

  ValueNotifier<ChatMessage?> get streamingMessage => _stream.streamingMessage;
  String? get streamingMessageId => _stream.messageId;
  ValueNotifier<AgentLiveness?> get agentLiveness => _liveness.notifier;

  void _syncStreamingIntoList() => _stream.sync(_upsertIntoList);

  Future<void> refreshConversations() async => conversationList.load();

  /// Observe a follow-up already accepted by a visual submission.
  void followServerResponse(String conversationId) {
    if (_currentConversation?.id != conversationId || isSending) return;
    _recovery.begin(
      conversationId: conversationId,
      currentMessages: _messages,
      initialState: ChatResponseRecoveryState.syncing,
    );
    _notifySafely();
  }

  bool _syncingFromServer = false;

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

  Future<void> loadConversation(String conversationId) =>
      _openConversation(conversationId);

  Future<void> _openConversation(
    String conversationId, {
    bool adoptPendingFolder = false,
  }) async {
    final navigation = _detachStreamForNavigation();
    final actionEpoch = _actionEpoch;
    _isOpeningConversation = true;
    _clearError();
    _notifySafely();
    final starEpoch = _stars.epoch;
    try {
      await navigation;
      final conversation = await _chatService.getConversation(
        conversationId,
        messageLimit: _messageWindow,
      );
      if (actionEpoch != _actionEpoch || _disposed) return;
      _messages = [
        for (final msg in hydrateMessageAttachments(
          conversation.messages ?? [],
        ))
          _stars.mergeConfirmed(conversationId, msg, starEpoch),
      ];
      _currentConversation = conversation.copyWith(messages: _messages);
      _setErrorContext();
      if (adoptPendingFolder) {
        await _folders.adoptPending(conversationId);
      } else {
        unawaited(_folders.clear(null));
      }
    } catch (e) {
      if (actionEpoch != _actionEpoch) return;
      _setError('Failed to load conversation: $e');
    } finally {
      if (actionEpoch == _actionEpoch) _isOpeningConversation = false;
      _notifySafely();
    }
  }

  Future<void> applyTopicSwitch(TopicSwitchResponse response) async {
    final current = _currentConversation;
    if (current?.id != response.conversationId) {
      await _openConversation(
        response.conversationId,
        adoptPendingFolder: true,
      );
      final opened = _currentConversation;
      if (opened?.id != response.conversationId || _error != null) {
        throw StateError(_error ?? 'Could not open the topic conversation');
      }
      conversationList.prepend(opened!);
      _notifySafely();
      return;
    }
    if (current == null) return;
    if (_stream.isActive) await stopStreaming();
    _actionEpoch++;
    _messages = [];
    final switched = response.topic;
    _currentConversation = current.copyWith(
      title: switched?.label ?? current.title,
      messageCount: 0,
      messages: const [],
      hasMoreMessages: false,
      contextSummary: null,
      activeTopicId: switched?.id,
      activeTopic: switched == null
          ? null
          : topicNodeFromSwitched(
              switched,
              contextStatus: response.contextStatus,
            ),
      topicIsPinned: switched?.pinned ?? false,
      contextVersion: response.contextVersion,
      sessionEpoch: response.sessionEpoch,
    );
    _clearError();
    _updateConversationInList();
    _notifySafely();
  }

  void applyTopicCombine(TopicSwitchResponse response) {
    final current = _currentConversation;
    final combined = response.topic;
    if (current == null ||
        current.id != response.conversationId ||
        combined == null) {
      return;
    }
    _actionEpoch++;
    _currentConversation = current.copyWith(
      title: combined.label,
      activeTopicId: combined.id,
      activeTopic: topicNodeFromSwitched(
        combined,
        contextStatus: response.contextStatus,
      ),
      topicIsPinned: combined.pinned,
      contextVersion: response.contextVersion,
      sessionEpoch: response.sessionEpoch,
    );
    _updateConversationInList();
    _notifySafely();
  }

  Future<void>? _primaryEnsureFuture;

  Future<void> enterPrimaryConversation() {
    if (_currentConversation?.isPrimary == true) return Future.value();
    return _primaryEnsureFuture ??= _ensurePrimaryConversation();
  }

  Future<void> _ensurePrimaryConversation() async {
    final navigation = _detachStreamForNavigation();
    final actionEpoch = _actionEpoch;
    _isOpeningConversation = true;
    _error = null;
    _notifySafely();
    try {
      await navigation;
      final conversation = await _chatService.getOrCreatePrimary(
        model: _selectedModelId() ?? 'deepseek-v4.1-flash:cloud',
        systemPrompt: _pendingSystemPromptValue,
        thinkingLevel: _pendingThinkingLevelValue,
      );
      final detailed = await _chatService.getConversation(
        conversation.id,
        messageLimit: _messageWindow,
        silent: true,
      );
      if (actionEpoch != _actionEpoch) return;
      _currentConversation = detailed;
      _messages = hydrateMessageAttachments(detailed.messages ?? const []);
      _setErrorContext();
    } catch (error) {
      if (actionEpoch != _actionEpoch) return;
      _error = 'Failed to open your primary chat: $error';
      logDebug(_error!);
    } finally {
      _primaryEnsureFuture = null;
      if (actionEpoch == _actionEpoch) _isOpeningConversation = false;
      _notifySafely();
    }
  }

  Future<void> loadOlderMessages() async {
    final conversation = _currentConversation;
    if (conversation == null ||
        !conversation.hasMoreMessages ||
        _loadingOlderMessages ||
        _messages.isEmpty) {
      return;
    }

    _loadingOlderMessages = true;
    _notifySafely();

    final oldestId = _messages.first.id;
    try {
      final (older, hasMore) = await _chatService.getOlderMessages(
        conversation.id,
        oldestId,
      );
      if (_currentConversation?.id == conversation.id) {
        _messages = [...hydrateMessageAttachments(older), ..._messages];
        _currentConversation = conversation.copyWith(hasMoreMessages: hasMore);
      }
    } catch (e) {
      logDebug('Failed to load older messages: $e');
    } finally {
      _loadingOlderMessages = false;
      _notifySafely();
    }
  }

  Future<Conversation?> createConversation({
    String? title,
    String? model,
    String? initialMessage,
    String? systemPrompt,
    ThinkingLevel? thinkingLevel,
    String? activeTopicId,
    List<ChatAttachment> initialAttachments = const [],
  }) async {
    final navigation = _detachStreamForNavigation();
    final actionEpoch = _actionEpoch;
    _isOpeningConversation = true;
    _clearError();
    _notifySafely();

    try {
      await navigation;
      final selectedModel =
          model ?? _selectedModelId() ?? 'deepseek-v4.1-flash:cloud';
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
        activeTopicId: activeTopicId,
      );

      final detailed = await _chatService.getConversation(
        conversation.id,
        messageLimit: _messageWindow,
      );
      if (actionEpoch != _actionEpoch) return null;

      _currentConversation = detailed;
      _messages = hydrateMessageAttachments(detailed.messages ?? []);
      _setErrorContext();

      await _folders.adoptPending(conversation.id);
      if (actionEpoch != _actionEpoch || _disposed) return null;
      _isOpeningConversation = false;

      conversationList.prepend(detailed);
      _notifySafely();

      if ((initialMessage?.isNotEmpty ?? false) ||
          initialAttachments.isNotEmpty) {
        await sendMessage(
          initialMessage ?? '',
          attachments: initialAttachments,
        );
      } else {
        _notifySafely();
      }

      await conversationList.load();
      return detailed;
    } catch (e) {
      if (actionEpoch != _actionEpoch) return null;
      _setError('Failed to create conversation: $e');
      _isSending = false;
      logDebug(_error!);
      _notifySafely();
      return null;
    } finally {
      if (actionEpoch == _actionEpoch) _isOpeningConversation = false;
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

    _clearError();
    _notifySafely();

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
      _setError('Failed to update conversation: $e');
      _notifySafely();
    }
  }

  Future<bool> switchModelAndRetryLastTurn(String modelId) async {
    final conversation = _currentConversation;
    if (conversation == null || isSending) return false;

    _clearError();
    _isSending = true;
    _notifySafely();

    try {
      await _stream.cancel();
      _syncStreamingIntoList();
      _stream.clear();

      await _chatService.updateConversation(conversation.id, model: modelId);
      final refreshed = await _chatService.getConversation(
        conversation.id,
        messageLimit: _messageWindow,
      );
      _currentConversation = refreshed;
      _messages = hydrateMessageAttachments(refreshed.messages ?? []);

      final userIndex = _messages.lastIndexWhere((message) => message.isUser);
      if (userIndex < 0) {
        throw StateError('No user message is available to retry');
      }
      final userMessage = _messages[userIndex];
      _isSending = false;
      await editUserMessage(
        userMessage.id,
        stripAttachedFileMarker(userMessage.content),
      );
      return true;
    } catch (e) {
      _isSending = false;
      _setError('Failed to switch models and retry: $e');
      _notifySafely();
      return false;
    }
  }

  Future<void> togglePin(String conversationId) async {
    final updated = await conversationList.togglePin(conversationId);
    if (updated != null && _currentConversation?.id == conversationId) {
      _currentConversation = updated;
      _notifySafely();
    }
  }

  Future<void> setMute(String conversationId, String duration) async {
    final updated = await conversationList.setMute(conversationId, duration);
    if (updated != null && _currentConversation?.id == conversationId) {
      _currentConversation = updated;
      _notifySafely();
    }
  }

  String? clientFolderFor(String? conversationId) =>
      _folders.folderFor(conversationId);

  String? clientFolderNameFor(String? conversationId) =>
      _folders.folderNameFor(conversationId);

  Future<void> attachClientFolder(String? conversationId, String path) =>
      _folders.attach(conversationId, path);

  Future<void> clearClientFolder(String? conversationId) =>
      _folders.clear(conversationId);

  Future<void> deleteConversation(String conversationId) async {
    _clearError();
    _actionEpoch++;

    if (_currentConversation?.id == conversationId) {
      _currentConversation = null;
      _messages = [];
      _notifySafely();
    }
    conversationList.delete(conversationId);
  }

  void undoDeleteConversation(String conversationId) =>
      conversationList.undoDelete(conversationId);

  void clearCurrentConversation() {
    unawaited(_detachStreamForNavigation());
    _isOpeningConversation = false;
    _currentConversation = null;
    _messages = [];
    _recovery.cancel();
    _clearError();
    _notifySafely();
  }

  bool get hasActiveConversation => _currentConversation != null;

  void addAttachments(List<ChatAttachment> attachments) {
    _pendingAttachments ??= [];
    _pendingAttachments!.addAll(attachments);
    _notifySafely();
  }

  List<ChatAttachment>? _pendingAttachments;
  List<ChatAttachment>? get pendingAttachments => _pendingAttachments;

  void clearPendingAttachments() {
    _pendingAttachments = null;
    _notifySafely();
  }

  void _updateConversationInList() {
    final current = _currentConversation;
    if (current != null) conversationList.replaceEntry(current);
  }

  Future<void> sendMessage(
    String content, {
    List<ChatAttachment> attachments = const [],
    String? talkModeInstruction,
  }) async {
    if (content.trim().isEmpty && attachments.isEmpty) return;

    final primaryEnsure = _primaryEnsureFuture;
    if (primaryEnsure != null) {
      await primaryEnsure;
      if (_currentConversation == null) return;
    }

    if (isSending) return;

    if (_currentConversation?.isPrimary == true) {
      onConversationStarted?.call();
    }

    _clearError();
    _actionEpoch++;

    if (_currentConversation == null) {
      await createConversation(
        model: _selectedModelId() ?? 'deepseek-v4.1-flash:cloud',
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

    if (_currentConversation != null) {
      _currentConversation = _currentConversation!.copyWith(
        messageCount: _messages.length,
      );
      _updateConversationInList();
    }
    _notifySafely();

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
      _setError(friendlyStreamError(e));
      _isSending = false;
      _notifySafely();
    }
  }

  Future<void> regenerateLastAssistant() async {
    if (_currentConversation == null || isSending) return;

    final lastAssistantIdx = _messages.lastIndexWhere(
      (m) => m.isAssistant && !m.id.startsWith('temp-'),
    );
    if (lastAssistantIdx < 0) return;
    final messageId = _messages[lastAssistantIdx].id;

    _clearError();
    _actionEpoch++;
    _isSending = true;
    _messages = _messages.sublist(0, lastAssistantIdx);
    _notifySafely();

    try {
      final stream = _chatService.regenerateMessage(
        _currentConversation!.id,
        messageId,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _setError(friendlyStreamError(e));
      _isSending = false;
      _notifySafely();
    }
  }

  Future<void> editUserMessage(String messageId, String newContent) async {
    if (_currentConversation == null || isSending) return;
    if (newContent.trim().isEmpty) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final target = _messages[idx];
    if (!target.isUser) return;

    _clearError();
    _actionEpoch++;
    _isSending = true;

    final edited = target.copyWith(content: newContent);
    _messages = [..._messages.sublist(0, idx), edited];
    _notifySafely();

    try {
      final stream = _chatService.editMessage(
        _currentConversation!.id,
        messageId,
        newContent,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _setError(friendlyStreamError(e));
      _isSending = false;
      _notifySafely();
    }
  }

  Future<void> branchFromMessage(String messageId) async {
    if (_currentConversation == null) return;

    _clearError();
    _notifySafely();

    try {
      final newConv = await _chatService.branchConversation(
        _currentConversation!.id,
        messageId,
      );
      conversationList.prepend(newConv);
      await loadConversation(newConv.id);
    } catch (e) {
      _setError('Failed to branch conversation: $e');
      _notifySafely();
    }
  }

  void _consumeAssistantStream(Stream<ChatResponseChunk> stream) {
    final assistantMessageId = 'temp-${_uuid.v4()}';
    final streamConversationId = _currentConversation?.id;
    final streamActionEpoch = _actionEpoch;
    bool ownsCurrentState() =>
        streamActionEpoch == _actionEpoch &&
        streamConversationId == _currentConversation?.id;
    ErrorReporter.instance.setContext(
      conversationId: streamConversationId,
      context: {'surface': 'chat'},
    );
    var accumulatedContent = '';
    var accumulatedThinking = '';

    ChatMessage current([Map<String, dynamic>? doneMetadata]) =>
        buildStreamingAssistantMessage(
          assistantMessageId,
          accumulatedContent,
          accumulatedThinking,
          doneMetadata,
        );

    _upsertIntoList(current());
    _stream.push(current(), force: true);
    _notifySafely();

    _stream.listen(
      stream,
      messageId: assistantMessageId,
      onChunk: (chunk) {
        if (chunk.isClientToolRequest) {
          final request = chunk.clientToolRequest;
          if (!_disposed && streamConversationId != null && request != null) {
            unawaited(_folders.serveToolRequest(streamConversationId, request));
          }
          return;
        }
        if (!ownsCurrentState()) return;
        if (chunk.type == 'topic_update') {
          onTopicUpdate?.call(extractDynamicEventPayload(chunk));
        } else if (chunk.type == 'context_preparing') {
          onContextPreparing?.call(extractDynamicEventPayload(chunk));
        } else if (chunk.type == 'context_update') {
          onContextUpdate?.call({
            ...extractDynamicEventPayload(chunk),
            'conversation_id': streamConversationId,
          });
        } else if (chunk.type == 'topic_drift') {
          onTopicDrift?.call(extractDynamicEventPayload(chunk));
        } else if (chunk.isThinking && chunk.content != null) {
          accumulatedThinking += chunk.content!;
          _stream.push(current());
        } else if (chunk.isChunk && chunk.content != null) {
          accumulatedContent += chunk.content!;
          _stream.push(current());
        } else if (chunk.isToolCall) {
          _syncStreamingIntoList();
          _messages = insertMessagesBeforeAnchor(
            _messages,
            assistantMessageId,
            buildTempToolCallMessages(chunk.toolCalls ?? const []),
          );
          _notifySafely();
        } else if (chunk.isToolResult) {
          _syncStreamingIntoList();
          final resultMsg = buildTempToolResultMessage(chunk.toolResult);
          if (resultMsg != null) {
            _messages = insertMessagesBeforeAnchor(
              _messages,
              assistantMessageId,
              [resultMsg],
            );
          }
          final tr = chunk.toolResult;
          if (tr != null) {
            panel.openFromToolResult(tr.toolName, tr.result);
          }
          _notifySafely();
        } else if (chunk.isToolExecution) {
          _applyToolExecution(chunk.toolExecution);
        } else if (chunk.isHeartbeat) {
          _liveness.applyHeartbeat(chunk.heartbeat);
        } else if (chunk.isDone) {
          // Emitted per LLM iteration (tool-call iteration + final answer).
          // Commit iteration metadata without ending the SSE stream.
          if (accumulatedContent.isNotEmpty || accumulatedThinking.isNotEmpty) {
            final committed = current(chunk.metadata);
            _upsertIntoList(committed);
            _stream.push(committed, force: true);
            _notifySafely();
          }
        } else if (chunk.isError) {
          _syncStreamingIntoList();
          _setError(chunk.error ?? 'An error occurred', meta: chunk.metadata);
          _isSending = false;
          _notifySafely();
        }
      },
      onError: (e) {
        if (!ownsCurrentState()) return;
        _syncStreamingIntoList();
        _isSending = false;
        logDebug('Stream error: $e');
        _stream.clear();
        _liveness.reset();
        final connErr = isStreamConnectionError(e);
        if (connErr) {
          _clearError();
          final id = _currentConversation?.id;
          if (id != null) {
            _recovery.begin(conversationId: id, currentMessages: _messages);
          }
        } else {
          _setError(friendlyStreamError(e));
        }
        _notifySafely();
        if (!connErr) _reloadCurrentConversation();
      },
      onDone: () {
        if (!ownsCurrentState()) return;
        _isSending = false;
        _syncStreamingIntoList();
        _stream.clear();
        _liveness.reset();
        if (accumulatedContent.isEmpty && accumulatedThinking.isEmpty) {
          _messages = _messages
              .where((m) => m.id != assistantMessageId)
              .toList();
        }
        if (_currentConversation != null) {
          _currentConversation = _currentConversation!.copyWith(
            messageCount: _messages.length,
          );
          _updateConversationInList();
        }
        _notifySafely();
        _reloadCurrentConversation();
        _scheduleTitleRefresh();
      },
    );
  }

  void _setErrorContext({String? messageId}) {
    ErrorReporter.instance.setContext(
      conversationId: _currentConversation?.id,
      messageId: messageId,
      context: {'surface': 'chat'},
    );
  }

  Future<void> _detachStreamForNavigation() {
    _actionEpoch++;
    _recovery.cancel();
    _isSending = false;
    _stream.detach();
    _stream.clear();
    return Future.value();
  }

  Future<void> stopStreaming() async {
    if (_isOpeningConversation) return;
    unawaited(_stream.cancel());
    _isSending = false;
    _recovery.cancel();
    _actionEpoch++;
    final pending = streamingMessage.value;
    if (pending != null && pending.id == streamingMessageId) {
      _upsertIntoList(
        pending.copyWith(metadata: {...?pending.metadata, 'stopped': true}),
      );
    }
    _stream.clear();
    _notifySafely();

    if (_currentConversation != null) {
      try {
        await _chatService.stopStreaming(_currentConversation!.id);
      } catch (e) {
        logDebug('Failed to stop streaming on backend: $e');
      }
    }
  }

  void _upsertIntoList(ChatMessage message) {
    _messages = upsertMessageInList(_messages, message);
  }

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
    _liveness.noteSignal();
    _notifySafely();
  }

  int _actionEpoch = 0;

  @visibleForTesting
  Future<bool> reloadCurrentConversationForTest() =>
      _reloadCurrentConversation();

  Future<bool> _reloadCurrentConversation() async {
    final id = _currentConversation?.id;
    if (id == null) return false;
    if (_stars.hasPendingFor(id)) return false;
    final epoch = _actionEpoch;
    final starEpoch = _stars.epoch;
    try {
      final needed = _messages.length < _messageWindow
          ? _messageWindow
          : _messages.length;
      final conversation = await _chatService.getConversation(
        id,
        messageLimit: needed > _maxMessageLimit ? null : needed,
        silent: true,
      );
      if (epoch != _actionEpoch ||
          starEpoch != _stars.epoch ||
          _currentConversation?.id != id) {
        return false;
      }
      _currentConversation = conversation;
      _messages = hydrateMessageAttachments(conversation.messages ?? []);
      _recovery.completeIfArrived(_messages);
      _notifySafely();
      return true;
    } catch (e) {
      logDebug('Failed to reload conversation: $e');
      return false;
    }
  }

  Timer? _titleRefreshTimer;

  void _scheduleTitleRefresh() {
    _titleRefreshTimer?.cancel();
    _titleRefreshTimer = Timer(const Duration(seconds: 4), () async {
      if (_disposed || _isSending) return;
      await conversationList.load();
      if (_disposed) return;
      final id = _currentConversation?.id;
      if (id == null) return;
      final list = conversationList.conversations;
      final idx = list.indexWhere((c) => c.id == id);
      if (idx >= 0 && list[idx].title != _currentConversation!.title) {
        _currentConversation = _currentConversation!.copyWith(
          title: list[idx].title,
        );
        _notifySafely();
      }
    });
  }

  void clearError() {
    _clearError();
    if (conversationList.error != null) {
      conversationList.clearError();
    }
    _notifySafely();
  }

  @override
  void dispose() {
    _disposed = true;
    _stream.dispose();
    _recovery.dispose();
    _liveness.dispose();
    _titleRefreshTimer?.cancel();
    panel.dispose();
    conversationList.dispose();
    super.dispose();
  }
}
