import 'package:flutter/foundation.dart';

/// Platform checks that are safe to evaluate on every platform (no dart:io
/// at the call site; on web [defaultTargetPlatform] reflects the host OS,
/// which the [kIsWeb] guard excludes).
class PlatformInfo {
  /// A stable, web-safe platform label for diagnostics and backend metadata.
  static String get classification {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Platforms for which Garbanzo AI publishes and installs release assets.
  static bool get supportsSelfUpdate => isLinux || isWindows || isAndroid;
}
