import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/friends/models/share_models.dart';

/// REST client for sharing styles / prompt templates with friends
/// (`/api/v1/shares`). Copy-on-accept: accepting materializes the snapshot
/// as the caller's own style/template.
class SharesService {
  SharesService._();
  static final SharesService instance = SharesService._();

  /// Test seam — mirrors `FriendsService.forTesting`.
  SharesService.forTesting();

  final _api = ApiClient.instance;

  /// Shares a style or prompt template ([kind] 'style' | 'prompt') with a
  /// friend. Throws with the backend's message on business-rule errors
  /// (not friends, item not found).
  Future<void> share({
    required String kind,
    required String itemId,
    required String recipientEmail,
  }) async {
    final resp = await _api.post(
      '/api/v1/shares',
      data: {
        'kind': kind,
        'item_id': itemId,
        'recipient_email': recipientEmail,
      },
    );
    if (resp.statusCode != 201) throw _error(resp);
  }

  Future<List<SharedItem>> incoming() async {
    final resp = await _api.get('/api/v1/shares/incoming');
    if (resp.statusCode == 200) {
      return ((resp.data as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SharedItem.fromJson)
          .toList();
    }
    throw _error(resp);
  }

  /// Accepts a share; returns the id of the created copy.
  Future<String> accept(String shareId) async {
    final resp = await _api.post('/api/v1/shares/$shareId/accept');
    if (resp.statusCode == 200) {
      final data = resp.data;
      return data is Map<String, dynamic>
          ? (data['created_id'] as String? ?? '')
          : '';
    }
    throw _error(resp);
  }

  Future<void> decline(String shareId) async {
    final resp = await _api.post('/api/v1/shares/$shareId/decline');
    if (resp.statusCode != 204) throw _error(resp);
  }

  Exception _error(dynamic response) {
    final body = response.data;
    final detail = body is Map<String, dynamic>
        ? (body['detail'] as String? ?? 'Unknown error')
        : '$body';
    return Exception('API Error (${response.statusCode}): $detail');
  }
}
