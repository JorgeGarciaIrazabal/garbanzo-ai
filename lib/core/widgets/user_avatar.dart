import 'dart:convert';

import 'package:flutter/material.dart';

/// A [CircleAvatar] that shows the user's profile picture when available,
/// falling back to text initials on a coloured background.
///
/// [profilePictureB64] is a base64-encoded JPEG stored in the database.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.profilePictureB64,
    this.displayName,
    this.backgroundColor,
    this.foregroundColor,
    this.radius = 22,
  });

  final String? profilePictureB64;
  final String? displayName;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (profilePictureB64 != null && profilePictureB64!.isNotEmpty) {
      try {
        final bytes = const Base64Decoder().convert(profilePictureB64!);
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor ?? Colors.grey.shade300,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        // Fall through to initials
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Text(
        _initials(displayName ?? '?'),
        style: TextStyle(color: foregroundColor),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+|@'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    if (parts.length == 1) return first.toUpperCase();
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }
}
