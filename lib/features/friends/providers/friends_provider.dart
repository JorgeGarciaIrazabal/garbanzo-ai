import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/models/share_models.dart';
import 'package:garbanzo_ai/features/friends/services/friends_service.dart';
import 'package:garbanzo_ai/features/friends/services/shares_service.dart';

/// State for the Friends page: accepted friends plus pending requests in
/// both directions. All mutations re-fetch the full list afterwards — the
/// backend collapses states in non-obvious ways (e.g. sending a request to
/// someone who already asked you auto-accepts), so server truth beats
/// optimistic bookkeeping here.
class FriendsProvider extends ChangeNotifier with GuardedStateMixin {
  FriendsProvider({FriendsService? service, SharesService? sharesService})
    : _service = service ?? FriendsService.instance,
      _shares = sharesService ?? SharesService.instance {
    refresh();
  }

  final FriendsService _service;
  final SharesService _shares;

  FriendsList _list = const FriendsList();
  List<SharedItem> _incomingShares = const [];

  /// Styles/prompts friends shared with this user, pending accept/decline.
  List<SharedItem> get incomingShares => _incomingShares;

  List<Friend> get friends => _list.friends;
  List<FriendRequest> get incomingRequests => _list.incomingRequests;
  List<FriendRequest> get outgoingRequests => _list.outgoingRequests;
  List<Friend> get blocked => _list.blocked;

  Future<void> refresh() async {
    await runGuarded('Failed to load friends', () async {
      _list = await _service.list();
      _incomingShares = await _shares.incoming();
    });
  }

  /// Sends a request to [email]. Returns the resulting status ("pending" or
  /// "accepted") on success, null on failure (with [error] set — the backend
  /// message covers unknown emails and duplicates).
  Future<String?> sendRequest(String email) async {
    return runGuarded('Failed to send friend request', () async {
      final status = await _service.sendRequest(email);
      _list = await _service.list();
      return status;
    }, trackLoading: false);
  }

  Future<bool> accept(FriendRequest request) async {
    final ok = await runGuarded('Failed to accept request', () async {
      await _service.accept(request.id);
      _list = await _service.list();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  Future<bool> decline(FriendRequest request) async {
    final ok = await runGuarded('Failed to decline request', () async {
      await _service.decline(request.id);
      _list = await _service.list();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  /// Removes an accepted friend, or cancels an outgoing pending request
  /// (same DELETE endpoint — the backend resolves the pair either way).
  Future<bool> remove(String email) async {
    final ok = await runGuarded('Failed to remove friend', () async {
      await _service.remove(email);
      _list = await _service.list();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  /// Blocks [email] — replaces any friendship or pending request between
  /// the two users and stops new ones (plus room invites) both ways.
  Future<bool> block(String email) async {
    final ok = await runGuarded('Failed to block user', () async {
      await _service.block(email);
      _list = await _service.list();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  Future<bool> unblock(String email) async {
    final ok = await runGuarded('Failed to unblock user', () async {
      await _service.unblock(email);
      _list = await _service.list();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  /// Shares a style or prompt template with a friend.
  Future<bool> shareItem({
    required String kind,
    required String itemId,
    required String recipientEmail,
  }) async {
    final ok = await runGuarded('Failed to share', () async {
      await _shares.share(
        kind: kind,
        itemId: itemId,
        recipientEmail: recipientEmail,
      );
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  /// Accepts a share — the copy lands in the user's styles/templates.
  Future<bool> acceptShare(SharedItem item) async {
    final ok = await runGuarded('Failed to accept share', () async {
      await _shares.accept(item.id);
      _incomingShares = await _shares.incoming();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  Future<bool> declineShare(SharedItem item) async {
    final ok = await runGuarded('Failed to decline share', () async {
      await _shares.decline(item.id);
      _incomingShares = await _shares.incoming();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }
}
