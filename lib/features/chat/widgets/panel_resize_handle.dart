import 'package:flutter/material.dart';

/// Draggable divider that resizes the micro-app side panel. Drag left/right to
/// widen/narrow; double-click to reset to the default width.
class PanelResizeHandle extends StatelessWidget {
  const PanelResizeHandle({
    super.key,
    required this.onDrag,
    required this.onReset,
  });

  /// Called with the horizontal drag delta (dx) on each move.
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onDoubleTap: onReset,
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 1,
              color: theme.dividerColor,
              child: Center(
                child: Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
