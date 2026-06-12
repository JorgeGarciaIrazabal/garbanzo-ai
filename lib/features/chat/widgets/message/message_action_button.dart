import 'package:flutter/material.dart';

/// Shared compact action button for message action rows
/// (Copy, Listen, Regenerate, Branch, Edit, Info…).
///
/// Renders a 14px icon + 12px label with a [tooltip] for discoverability
/// and an explicit button role + label for screen readers.
class MessageActionButton extends StatelessWidget {
  const MessageActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  /// Use the primary color for active/toggled states ("Copied!", playing).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = highlighted
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
