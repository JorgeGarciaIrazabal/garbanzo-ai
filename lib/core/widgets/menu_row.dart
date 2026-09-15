import 'package:flutter/material.dart';

/// A menu entry with a leading icon, used by the sidebar thread/room actions
/// menus.
///
/// The label shrinks and ellipsizes rather than forcing the popup wider: a
/// translated label ("Descargar transcripción") is longer than the English one
/// and would otherwise overflow the menu's max width.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
