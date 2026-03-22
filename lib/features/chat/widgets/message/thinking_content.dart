import 'package:flutter/material.dart';

/// Displays expandable thinking content.
class ThinkingContent extends StatefulWidget {
  const ThinkingContent({
    super.key,
    required this.thinkingContent,
    required this.colorScheme,
    required this.textTheme,
  });

  final String thinkingContent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  State<ThinkingContent> createState() => _ThinkingContentState();
}

class _ThinkingContentState extends State<ThinkingContent> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 14,
                  color: widget.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _isExpanded ? 'Hide thinking' : 'Show thinking',
                  style: widget.textTheme.labelSmall?.copyWith(
                    color: widget.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: widget.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thinking Process',
                  style: widget.textTheme.labelSmall?.copyWith(
                    color: widget.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  widget.thinkingContent,
                  style: widget.textTheme.bodySmall?.copyWith(
                    color: widget.colorScheme.onSurfaceVariant,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
