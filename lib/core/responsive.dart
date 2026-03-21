import 'package:flutter/widgets.dart';

/// Shared responsive breakpoints as a [BuildContext] extension.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Wide layout — show sidebar, expanded views.
  bool get isWide => screenWidth > 800;

  /// Narrow layout — use drawer, compact views.
  bool get isNarrow => screenWidth <= 800;
}
