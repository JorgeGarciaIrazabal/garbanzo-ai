import 'package:flutter/material.dart';

/// Displays expandable thinking content.
///
/// Auto-expand semantics (until the user manually toggles the section):
/// - [isLive] becomes true → expand, so the user sees reasoning tokens stream.
/// - [hasContent] becomes true → collapse, since the final answer is in.
/// - [isLive] flips false on its own (e.g. a tool call elsewhere caused this
///   message to stop being the trailing one) → leave the section open so the
///   reasoning that led to the tool stays visible.
class ThinkingContent extends StatefulWidget {
  const ThinkingContent({
    super.key,
    required this.thinkingContent,
    required this.colorScheme,
    required this.textTheme,
    this.isLive = false,
    this.hasContent = false,
  });

  final String thinkingContent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isLive;
  final bool hasContent;

  @override
  State<ThinkingContent> createState() => _ThinkingContentState();
}

class _ThinkingContentState extends State<ThinkingContent> {
  late bool _isExpanded = widget.isLive;
  bool _userToggled = false;

  @override
  void didUpdateWidget(covariant ThinkingContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_userToggled) return;
    if (widget.isLive && !oldWidget.isLive) {
      _isExpanded = true;
    }
    if (widget.hasContent && !oldWidget.hasContent) {
      _isExpanded = false;
    }
  }

  void _toggle() {
    setState(() {
      _userToggled = true;
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final headerColor = widget.isLive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.75);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: headerColor,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _isExpanded ? 'Hide thinking' : 'Show thinking',
                    style: widget.textTheme.labelMedium?.copyWith(
                      color: headerColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: headerColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 12, top: 4),
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
            ),
            child: SelectableText(
              widget.thinkingContent,
              style: widget.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
