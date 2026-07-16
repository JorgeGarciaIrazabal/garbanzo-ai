import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';

/// REST client for the friends graph (`/api/v1/friends`).
///
/// [ApiClient] never throws on non-2xx (`validateStatus` accepts all), so
/// every call checks the status code and throws an
/// `Exception('API Error (NNN): detail')` — the shape
/// `describeFailure`/`GuardedStateMixin` knows how to present.
class FriendsService {
  FriendsService._();
  static final FriendsService instance = FriendsService._();

  /// Test seam — mirrors `StyleService.forTesting`.
  FriendsService.forTesting();

  final _api = ApiClient.instance;

  Future<FriendsList> list() async {
    final resp = await _api.get('/api/v1/friends');
    if (resp.statusCode == 200) {
      return FriendsList.fromJson(resp.data as Map<String, dynamic>);
    }
    throw _error(resp);
  }

  /// Sends a request; returns the resulting status ("pending", or
  /// "accepted" when the other side had already asked). Throws with the
  /// backend's message on business-rule errors (unknown email, duplicates).
  Future<String> sendRequest(String email) async {
    final resp = await _api.post(
      '/api/v1/friends/requests',
      data: {'email': email.trim()},
    );
    if (resp.statusCode == 201) {
      final data = resp.data;
      return data is Map<String, dynamic>
          ? (data['status'] as String? ?? 'pending')
          : 'pending';
    }
    throw _error(resp);
  }

  Future<void> accept(String requestId) async {
    final resp = await _api.post('/api/v1/friends/requests/$requestId/accept');
    if (resp.statusCode != 200) throw _error(resp);
  }

  Future<void> decline(String requestId) async {
    final resp = await _api.post('/api/v1/friends/requests/$requestId/decline');
    if (resp.statusCode != 204) throw _error(resp);
  }

  /// Removes an accepted friend or cancels an outgoing pending request.
  Future<void> remove(String email) async {
    final resp = await _api.delete('/api/v1/friends/$email');
    if (resp.statusCode != 204) throw _error(resp);
  }

  /// Blocks a user — replaces any friendship or pending request.
  Future<void> block(String email) async {
    final resp = await _api.post('/api/v1/friends/$email/block');
    if (resp.statusCode != 204) throw _error(resp);
  }

  Future<void> unblock(String email) async {
    final resp = await _api.delete('/api/v1/friends/$email/block');
    if (resp.statusCode != 204) throw _error(resp);
  }

  Future<List<Friend>> search(String query) async {
    final resp = await _api.get(
      '/api/v1/friends/search',
      queryParameters: {'q': query},
    );
    if (resp.statusCode == 200) {
      return ((resp.data as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Friend.fromJson)
          .toList();
    }
    throw _error(resp);
  }

  Exception _error(dynamic response) {
    final body = response.data;
    final detail = body is Map<String, dynamic>
        ? (body['detail'] as String? ?? 'Unknown error')
        : '$body';
    return Exception('API Error (${response.statusCode}): $detail');
  }
}
