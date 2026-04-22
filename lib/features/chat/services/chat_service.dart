import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api_client.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/model_info.dart';

/// Service for interacting with the chat API.
///
/// All HTTP calls are routed through [ApiClient] so that base-URL resolution,
/// auth headers, and JSON encoding stay in one place.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final ApiClient _api = ApiClient.instance;

  // ==========================================================================
  // Conversations
  // ==========================================================================

  Future<Conversation> createConversation({
    String? title,
    String model = 'llama3.2',
    String? initialMessage,
    String? systemPrompt,
  }) async {
    final response = await _api.post(
      '/api/v1/chat/conversations',
      data: {
        'title': ?title,
        'model': model,
        'initial_message': ?initialMessage,
        'system_prompt': ?systemPrompt,
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

  Future<Conversation> getConversation(String conversationId) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId',
    );

    if (response.statusCode == 200) {
      return Conversation.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  Future<Conversation> updateConversation(
    String conversationId, {
    String? title,
    String? model,
    bool? useMemory,
    String? systemPrompt,
    bool clearSystemPrompt = false,
    List<String>? enabledTools,
    bool clearEnabledTools = false,
    bool? isPinned,
  }) async {
    // clearSystemPrompt=true sends "" to the backend to reset to user default.
    final effectivePrompt = clearSystemPrompt ? '' : systemPrompt;
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId',
      data: {
        'title': ?title,
        'model': ?model,
        'use_memory': ?useMemory,
        'is_pinned': ?isPinned,
        if (clearSystemPrompt || effectivePrompt != null)
          'system_prompt': effectivePrompt,
        if (clearEnabledTools) 'enabled_tools': null,
        if (!clearEnabledTools && enabledTools != null)
          'enabled_tools': enabledTools,
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
  }) {
    return _sseStream(
      '/api/v1/chat/conversations/$conversationId/chat',
      {
        'message': message,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
        'options': _buildOptions(temperature, maxTokens, topP),
      },
    );
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
      final errorBody =
          await byteStream.cast<List<int>>().transform(utf8.decoder).join();
      throw Exception('Chat failed: ${response.statusCode} - $errorBody');
    }

    await for (final chunk
        in byteStream.cast<List<int>>().transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('data: ')) {
          final jsonStr = trimmed.substring(6);
          if (jsonStr.isNotEmpty && jsonStr != '[DONE]') {
            try {
              final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
              yield ChatResponseChunk.fromJson(decoded);
            } catch (e) {
              if (kDebugMode) {
                print('Failed to parse SSE chunk: $jsonStr');
              }
            }
          }
        }
      }
    }
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
