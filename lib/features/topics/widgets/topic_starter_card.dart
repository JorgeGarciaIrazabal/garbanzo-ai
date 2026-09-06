import 'package:flutter/material.dart';

class TopicStarterCard extends StatelessWidget {
  const TopicStarterCard({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        key: ValueKey('topic_starter_$text'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 12, height: 1.35),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_upward_rounded, size: 14, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
