import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Logs [message] via `dart:developer`'s `log()`, but only in debug builds.
///
/// Centralizes the `if (kDebugMode) print(...)` pattern used across
/// providers/services so debug output is consistent and easy to filter
/// (name: 'garbanzo') in DevTools / IDE logs.
void logDebug(String message) {
  if (kDebugMode) {
    log(message, name: 'garbanzo');
  }
}
