/// A user record returned by `/api/v1/admin/users`.
class AdminUser {
  final String email;
  final String? fullName;
  final DateTime? createdAt;
  final bool isAdmin;
  final bool isDisabled;

  const AdminUser({
    required this.email,
    this.fullName,
    this.createdAt,
    this.isAdmin = false,
    this.isDisabled = false,
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
    );
  }

  AdminUser copyWith({
    String? email,
    String? fullName,
    DateTime? createdAt,
    bool? isAdmin,
    bool? isDisabled,
  }) {
    return AdminUser(
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      createdAt: createdAt ?? this.createdAt,
      isAdmin: isAdmin ?? this.isAdmin,
      isDisabled: isDisabled ?? this.isDisabled,
    );
  }
}
