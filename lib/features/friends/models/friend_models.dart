/// One accepted friend, from the viewer's perspective.
class Friend {
  const Friend({
    required this.email,
    required this.friendshipId,
    this.fullName,
    this.since,
  });

  final String email;
  final String friendshipId;
  final String? fullName;
  final DateTime? since;

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : email;

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
    email: (json['email'] as String?) ?? '',
    friendshipId: (json['friendship_id'] as String?) ?? '',
    fullName: json['full_name'] as String?,
    since: DateTime.tryParse((json['since'] as String?) ?? ''),
  );
}

/// A pending friend request (either direction).
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.requesterEmail,
    required this.addresseeEmail,
    this.createdAt,
  });

  final String id;
  final String requesterEmail;
  final String addresseeEmail;
  final DateTime? createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
    id: (json['id'] as String?) ?? '',
    requesterEmail: (json['requester_email'] as String?) ?? '',
    addresseeEmail: (json['addressee_email'] as String?) ?? '',
    createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
  );
}

/// The full friends state (`GET /friends`).
class FriendsList {
  const FriendsList({
    this.friends = const [],
    this.incomingRequests = const [],
    this.outgoingRequests = const [],
    this.blocked = const [],
  });

  final List<Friend> friends;
  final List<FriendRequest> incomingRequests;
  final List<FriendRequest> outgoingRequests;

  /// Users this viewer has blocked (blocks against the viewer never appear).
  final List<Friend> blocked;

  factory FriendsList.fromJson(Map<String, dynamic> json) => FriendsList(
    friends: ((json['friends'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Friend.fromJson)
        .toList(),
    incomingRequests: ((json['incoming_requests'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FriendRequest.fromJson)
        .toList(),
    outgoingRequests: ((json['outgoing_requests'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FriendRequest.fromJson)
        .toList(),
    blocked: ((json['blocked'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Friend.fromJson)
        .toList(),
  );
}
