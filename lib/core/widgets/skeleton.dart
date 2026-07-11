import 'package:flutter/material.dart';

/// Gently pulses its child's opacity — the shared "loading" treatment for
/// skeleton placeholders. One pulse wraps a whole skeleton block so the
/// animation cost stays constant regardless of row count.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1.0,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _controller, child: widget.child);
  }
}

/// A single placeholder row shaped like a ListTile: optional leading circle
/// plus one or two text bars.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key, this.showAvatar = false, this.lines = 2});

  final bool showAvatar;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (showAvatar) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(0.7, 14),
                if (lines > 1) ...[const SizedBox(height: 8), bar(0.45, 10)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for list pages while their first load is in flight: a column
/// of pulsing [SkeletonListTile] rows. Use instead of a centered spinner so
/// the page keeps its layout shape.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 7,
    this.showAvatar = false,
    this.lines = 2,
  });

  final int itemCount;
  final bool showAvatar;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: (_, _) =>
            SkeletonListTile(showAvatar: showAvatar, lines: lines),
      ),
    );
  }
}
