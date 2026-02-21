import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_client.dart';
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
  }) async {
    final response = await _api.post(
      '/api/v1/chat/conversations',
      withAuth: true,
      body: {
        'title': ?title,
        'model': model,
        'initial_message': ?initialMessage,
      },
    );

    if (response.statusCode == 201) {
      return Conversation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
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
      return ConversationList.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    throw _handleError(response);
  }

  Future<Conversation> getConversation(String conversationId) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId',
    );

    if (response.statusCode == 200) {
      return Conversation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    throw _handleError(response);
  }

  Future<Conversation> updateConversation(
    String conversationId, {
    String? title,
    String? model,
  }) async {
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId',
      body: {
        'title': ?title,
        'model': ?model,
      },
    );

    if (response.statusCode == 200) {
      return Conversation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
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
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
  }) async* {
    final uri = _api.uri('/api/v1/chat/conversations/$conversationId/chat');

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';

    request.body = jsonEncode({
      'message': message,
      'options': {
        'temperature': temperature,
        'max_tokens': ?maxTokens,
        'top_p': ?topP,
        'stream': true,
      },
    });

    final response = await _api.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Chat failed: ${response.statusCode} - $body');
    }

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('data: ')) {
          final jsonStr = trimmed.substring(6);
          if (jsonStr.isNotEmpty && jsonStr != '[DONE]') {
            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              yield ChatResponseChunk.fromJson(data);
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

  Future<ModelList> listModels() async {
    final response = await _api.get('/api/v1/chat/models');

    if (response.statusCode == 200) {
      return ModelList.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    throw _handleError(response);
  }

  // ==========================================================================
  // Error Handling
  // ==========================================================================

  Exception _handleError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'] as String? ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    } catch (_) {
      return Exception(
        'API Error (${response.statusCode}): ${response.body}',
      );
    }
  }
}
