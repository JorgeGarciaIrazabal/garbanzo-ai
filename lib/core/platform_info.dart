import 'package:flutter/foundation.dart';

/// Platform checks that are safe to evaluate on every platform (no dart:io
/// at the call site; on web [defaultTargetPlatform] reflects the host OS,
/// which the [kIsWeb] guard excludes).
class PlatformInfo {
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
}
