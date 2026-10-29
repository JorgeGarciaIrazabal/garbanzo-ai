import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';

/// Uses the saved server action; the client never supplies a tool name or URL.
class VisualUIService {
  VisualUIService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final VisualUIService instance = VisualUIService();

  final ApiClient _api;

  Future<Map<String, dynamic>> state(
    String conversationId,
    String callId,
  ) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId/ui-actions',
      queryParameters: {'tool_call_id': callId},
    );
    expectStatus(response, const {
      200,
    }, operation: 'Failed to load UI action state');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> submit(
    String conversationId,
    Map<String, dynamic> submission,
  ) async {
    final response = await _api.post(
      '/api/v1/chat/conversations/$conversationId/ui-actions',
      data: submission,
    );
    expectStatus(response, const {
      200,
    }, operation: 'Failed to submit UI action');
    return Map<String, dynamic>.from(response.data as Map);
  }
}
