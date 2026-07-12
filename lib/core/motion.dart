import 'package:flutter/animation.dart';

/// Shared motion constants so animations feel consistent app-wide.
///
/// Defined alongside the theme (see `core/theme.dart`) per the identity work:
/// pick durations/curves once, reuse everywhere.
abstract final class Motion {
  /// Micro feedback: hovers, toggles, icon swaps.
  static const Duration fast = Duration(milliseconds: 150);

  /// Standard entrances: message appear, chips, small reveals.
  static const Duration medium = Duration(milliseconds: 250);

  /// Larger movements: panels, page-level reveals.
  static const Duration slow = Duration(milliseconds: 400);

  /// Default curve for entrances.
  static const Curve easeOut = Curves.easeOutCubic;

  /// Curve for larger, attention-carrying movements.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}
