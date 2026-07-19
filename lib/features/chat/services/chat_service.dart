import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

/// Service for interacting with the chat API.
///
/// All HTTP calls are routed through [ApiClient] so that base-URL resolution,
/// auth headers, and JSON encoding stay in one place.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  /// For tests only: lets a fake subclass exist outside this library.
  @visibleForTesting
  ChatService.forTesting();

  final ApiClient _api = ApiClient.instance;

  // ==========================================================================
  // Conversations
  // ==========================================================================

  Future<Conversation> createConversation({
    String? title,
    String model = 'llama3.2',
    String? initialMessage,
    String? systemPrompt,
    ThinkingLevel? thinkingLevel,
  }) async {
    final response = await _api.post(
      '/api/v1/chat/conversations',
      data: {
        'title': ?title,
        'model': model,
        'initial_message': ?initialMessage,
        'system_prompt': ?systemPrompt,
        'thinking_level': ?thinkingLevel?.name,
      },
    );

    if (response.statusCode == 201) {
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _api.get(
      '/api/v1/chat/conversations',
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );

    if (response.statusCode == 200) {
      return ConversationList.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  /// Fetch a conversation. Pass [messageLimit] to load only the most recent
  /// N messages instead of the full history (B-03) — much faster for long
  /// conversations; page older ones in with [getOlderMessages].
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
  }) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId',
      queryParameters: messageLimit != null
          ? {'message_limit': messageLimit.toString()}
          : null,
    );

    if (response.statusCode == 200) {
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  /// Page in messages older than [beforeMessageId] (B-03: scroll-to-top).
  /// Returns `(messages, hasMore)`.
  Future<(List<ChatMessage>, bool)> getOlderMessages(
    String conversationId,
    String beforeMessageId, {
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId/messages',
      queryParameters: {'before': beforeMessageId, 'limit': limit.toString()},
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final messages = (data['messages'] as List)
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList();
      return (messages, data['has_more'] as bool);
    }

    throw _handleError(response);
  }

  Future<Conversation> updateConversation(
    String conversationId, {
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
    // clearSystemPrompt=true sends "" to the backend to reset to user default.
    final effectivePrompt = clearSystemPrompt ? '' : systemPrompt;
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId',
      data: {
        'title': ?title,
        'model': ?model,
        'use_memory': ?useMemory,
        'use_knowledge_base': ?useKnowledgeBase,
        'is_pinned': ?isPinned,
        if (clearSystemPrompt || effectivePrompt != null)
          'system_prompt': effectivePrompt,
        if (clearEnabledTools) 'enabled_tools': null,
        if (!clearEnabledTools && enabledTools != null)
          'enabled_tools': enabledTools,
        // Three-way semantics: key absent = unchanged, null = reset to the
        // provider default ("Auto"), a value = set that level.
        if (setThinkingLevel || thinkingLevel != null)
          'thinking_level': thinkingLevel?.name,
      },
    );

    if (response.statusCode == 200) {
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  Future<void> stopStreaming(String conversationId) async {
    await _api.delete('/api/v1/chat/conversations/$conversationId/chat');
  }

  /// Mute or unmute notifications for the current user's conversation.
  ///
  /// [duration] is one of `8h`, `1w`, `forever`, `unmute` — validated
  /// server-side by the shared `MuteUpdate` schema (same request shape as the
  /// room mute endpoint).
  Future<Conversation> setMute(String conversationId, String duration) async {
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId/mute',
      data: {'duration': duration},
    );

    if (response.statusCode == 200) {
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  /// Return a client-served folder read to the in-flight turn (idea 17).
  ///
  /// The backend emits a `client_tool_request` chunk when the agent calls
  /// `read_file`/`list_files`; the desktop app reads the file locally and posts
  /// the result here so the parked turn can resume. The folder never leaves the
  /// client. [payload] carries `tool_call_id` plus either `data`/`filename`
  /// (read_file) or `entries` (list_files), or `ok:false` + `error`.
  Future<void> postClientToolResult(
    String conversationId,
    Map<String, dynamic> payload,
  ) async {
    await _api.post(
      '/api/v1/chat/conversations/$conversationId/client-tool-result',
      data: payload,
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    final response = await _api.delete(
      '/api/v1/chat/conversations/$conversationId',
    );

    if (response.statusCode != 204) {
      throw _handleError(response);
    }
  }

  // ==========================================================================
  // Chat Streaming
  // ==========================================================================

  /// Stream a chat response for a message via SSE.
  Stream<ChatResponseChunk> streamChatResponse(
    String conversationId,
    String message, {
    List<ChatAttachment> attachments = const [],
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
    bool hasClientFolder = false,
  }) {
    return _sseStream('/api/v1/chat/conversations/$conversationId/chat', {
      'message': message,
      if (attachments.isNotEmpty)
        'attachments': attachments.map((a) => a.toJson()).toList(),
      'options': _buildOptions(temperature, maxTokens, topP),
      // Tells the backend to advertise the client-served read_file/list_files
      // tools; when the model calls them we serve the read locally (idea 17).
      if (hasClientFolder) 'has_client_folder': true,
    });
  }

  /// Regenerate an assistant message; the prior one is deleted server-side.
  Stream<ChatResponseChunk> regenerateMessage(
    String conversationId,
    String messageId, {
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
  }) {
    return _sseStream(
      '/api/v1/chat/conversations/$conversationId/messages/$messageId/regenerate',
      {'options': _buildOptions(temperature, maxTokens, topP)},
    );
  }

  /// Edit a user message and re-run the conversation from that point.
  Stream<ChatResponseChunk> editMessage(
    String conversationId,
    String messageId,
    String newContent, {
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
  }) {
    return _sseStream(
      '/api/v1/chat/conversations/$conversationId/messages/$messageId/edit',
      {
        'content': newContent,
        'options': _buildOptions(temperature, maxTokens, topP),
      },
    );
  }

  Map<String, dynamic> _buildOptions(
    double temperature,
    int? maxTokens,
    double? topP,
  ) {
    return {
      'temperature': temperature,
      'max_tokens': ?maxTokens,
      'top_p': ?topP,
      'stream': true,
    };
  }

  Stream<ChatResponseChunk> _sseStream(
    String path,
    Map<String, dynamic> data,
  ) async* {
    final response = await _api.streamPost(path, data: data);

    final byteStream = (response.data as ResponseBody).stream;

    if (response.statusCode != 200) {
      final errorBody = await byteStream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      throw Exception('Chat failed: ${response.statusCode} - $errorBody');
    }

    yield* parseSseChunks(byteStream.cast<List<int>>().transform(utf8.decoder));
  }

  // ==========================================================================
  // Models
  // ==========================================================================

  Future<Conversation> branchConversation(
    String conversationId,
    String messageId,
  ) async {
    final response = await _api.post(
      '/api/v1/chat/conversations/$conversationId/messages/$messageId/branch',
    );

    if (response.statusCode == 201) {
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  // ==========================================================================
  // Models
  // ==========================================================================

  Future<ModelList> listModels() async {
    final response = await _api.get('/api/v1/chat/models');

    if (response.statusCode == 200) {
      return ModelList.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  // ==========================================================================
  // Error Handling
  // ==========================================================================

  Exception _handleError(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail'] as String? ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    }
    return Exception('API Error (${response.statusCode}): $body');
  }
}

/// Parse a stream of decoded UTF-8 text chunks (as delivered by the HTTP
/// client) into discrete [ChatResponseChunk]s.
///
/// SSE events are delimited by a blank line (`\n\n`). TCP may split a single
/// event across multiple byte chunks, so we buffer until we find a delimiter
/// before parsing — otherwise partial JSON frames silently fail to decode and
/// the UI looks "frozen" until the very end of the stream.
Stream<ChatResponseChunk> parseSseChunks(Stream<String> chunks) async* {
  var buffer = '';
  await for (final chunk in chunks) {
    buffer += chunk;
    while (true) {
      final delim = buffer.indexOf('\n\n');
      if (delim < 0) break;
      final event = buffer.substring(0, delim);
      buffer = buffer.substring(delim + 2);
      for (final line in event.split('\n')) {
        if (!line.startsWith('data: ')) continue;
        final jsonStr = line.substring(6);
        if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
        try {
          final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
          yield ChatResponseChunk.fromJson(decoded);
        } catch (e) {
          logDebug('Failed to parse SSE chunk: $jsonStr');
        }
      }
    }
  }
  if (buffer.isNotEmpty) {
    for (final line in buffer.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      final jsonStr = line.substring(6);
      if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
      try {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        yield ChatResponseChunk.fromJson(decoded);
      } catch (_) {
        /* drop */
      }
    }
  }
}
