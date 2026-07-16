import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';

/// REST client for the friends graph (`/api/v1/friends`).
class FriendsService {
  FriendsService._();
  static final FriendsService instance = FriendsService._();

  /// Test seam — mirrors `StyleService.forTesting`.
  FriendsService.forTesting();

  final _api = ApiClient.instance;

  Future<FriendsList> list() async {
    final resp = await _api.get('/api/v1/friends');
    return FriendsList.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Sends a request; returns the resulting status ("pending", or
  /// "accepted" when the other side had already asked). Throws with the
  /// backend's message on business-rule errors (unknown email, duplicates).
  Future<String> sendRequest(String email) async {
    try {
      final resp = await _api.post(
        '/api/v1/friends/requests',
        data: {'email': email.trim()},
      );
      final data = resp.data;
      return data is Map<String, dynamic>
          ? (data['status'] as String? ?? 'pending')
          : 'pending';
    } on DioException catch (e) {
      final detail = e.response?.data is Map<String, dynamic>
          ? (e.response!.data as Map<String, dynamic>)['detail'] as String?
          : null;
      throw Exception(detail ?? 'Failed to send friend request');
    }
  }

  Future<void> accept(String requestId) async {
    await _api.post('/api/v1/friends/requests/$requestId/accept');
  }

  Future<void> decline(String requestId) async {
    await _api.post('/api/v1/friends/requests/$requestId/decline');
  }

  /// Removes an accepted friend or cancels an outgoing pending request.
  Future<void> remove(String email) async {
    await _api.delete('/api/v1/friends/$email');
  }

  Future<List<Friend>> search(String query) async {
    final resp = await _api.get(
      '/api/v1/friends/search',
      queryParameters: {'q': query},
    );
    return ((resp.data as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Friend.fromJson)
        .toList();
  }
}
