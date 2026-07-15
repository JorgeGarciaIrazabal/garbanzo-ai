/// A user record returned by `/api/v1/admin/users`.
class AdminUser {
  final String email;
  final String? fullName;
  final DateTime? createdAt;
  final bool isAdmin;
  final bool isDisabled;
  final String? profilePictureB64;

  const AdminUser({
    required this.email,
    this.fullName,
    this.createdAt,
    this.isAdmin = false,
    this.isDisabled = false,
    this.profilePictureB64,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    final raw = json['created_at'];
    if (raw is String && raw.isNotEmpty) {
      parsed = DateTime.tryParse(raw);
    }
    return AdminUser(
      email: (json['email'] as String?) ?? '',
      fullName: json['full_name'] as String?,
      createdAt: parsed,
      isAdmin: json['is_admin'] as bool? ?? false,
      isDisabled: json['is_disabled'] as bool? ?? false,
      profilePictureB64: json['profile_picture_b64'] as String?,
    );
  }

  AdminUser copyWith({
    String? email,
    String? fullName,
    DateTime? createdAt,
    bool? isAdmin,
    bool? isDisabled,
    String? profilePictureB64,
  }) {
    return AdminUser(
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      createdAt: createdAt ?? this.createdAt,
      isAdmin: isAdmin ?? this.isAdmin,
      isDisabled: isDisabled ?? this.isDisabled,
      profilePictureB64: profilePictureB64 ?? this.profilePictureB64,
    );
  }
}
