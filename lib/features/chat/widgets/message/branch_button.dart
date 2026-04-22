import 'package:flutter/material.dart';

class BranchButton extends StatelessWidget {
  const BranchButton({super.key, required this.onPressed, this.enabled = true});

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context)
        .colorScheme
        .onSurfaceVariant
        .withValues(alpha: 0.6);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: 14, color: color),
            const SizedBox(width: 4),
            Text('Branch', style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
