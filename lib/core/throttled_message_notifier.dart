import 'dart:async';

import 'package:flutter/foundation.dart';

/// Buffers high-frequency streaming updates onto a [ValueNotifier] so only the
/// active bubble rebuilds at most once per [interval], rather than re-laying
/// out and re-parsing markdown on every SSE/WebSocket token.
class ThrottledMessageNotifier<T> {
  ThrottledMessageNotifier({
    required String Function(T message) idOf,
    this.interval = const Duration(milliseconds: 80),
  }) : _idOf = idOf;

  final String Function(T message) _idOf;
  final Duration interval;

  final ValueNotifier<T?> notifier = ValueNotifier(null);

  String? messageId;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flushTimer;
  T? _pending;

  void push(T message, {bool force = false}) {
    _pending = message;
    final now = DateTime.now();
    if (force || now.difference(_lastPush) >= interval) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _lastPush = now;
      notifier.value = message;
      return;
    }
    _flushTimer ??= Timer(interval, () {
      _flushTimer = null;
      _lastPush = DateTime.now();
      final pending = _pending;
      if (pending != null && _idOf(pending) == messageId) {
        notifier.value = pending;
      }
    });
  }

  /// Commits any buffered live content matching [messageId] via [upsert] before
  /// a structural list update so the transcript never lags behind the live view.
  void sync(void Function(T message) upsert) {
    final pending = _pending ?? notifier.value;
    if (pending != null && _idOf(pending) == messageId) {
      upsert(pending);
    }
  }

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending = null;
    messageId = null;
    notifier.value = null;
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    notifier.dispose();
  }
}
