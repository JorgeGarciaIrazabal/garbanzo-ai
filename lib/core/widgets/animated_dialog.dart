import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/motion.dart';

/// Shows a dialog with a fade + slight scale-up using the app's shared
/// [Motion] curves, so pop-ups feel consistent with message and page
/// transitions.
///
/// Drop-in replacement for [showDialog] when the dialog content provides its
/// own shape/shape-border (the default Material dialog already has rounded
/// corners — the scale here is subtle, 0.97 → 1.0).
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible
        ? MaterialLocalizations.of(context).modalBarrierDismissLabel
        : null,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: Motion.medium,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Motion.easeOut);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curve),
          alignment: Alignment.center,
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) => builder(context),
  );
}
