import 'package:garbanzo_ai/core/api_client.dart';

/// Uses the saved server action; the client never supplies a tool name or URL.
class VisualUIService {
  Future<Map<String, dynamic>> state(
    String conversationId,
    String callId,
  ) async {
    final response = await ApiClient.instance.get(
      '/api/v1/chat/conversations/$conversationId/ui-actions',
      queryParameters: {'tool_call_id': callId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> submit(
    String conversationId,
    Map<String, dynamic> submission,
  ) async {
    final response = await ApiClient.instance.post(
      '/api/v1/chat/conversations/$conversationId/ui-actions',
      data: submission,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
