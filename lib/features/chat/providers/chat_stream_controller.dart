import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

/// Owns the subscription and throttled live-message notifier for one chat turn.
class ChatStreamController {
  static const _pushInterval = Duration(milliseconds: 80);

  final ValueNotifier<ChatMessage?> streamingMessage = ValueNotifier(null);
  StreamSubscription<ChatResponseChunk>? _subscription;
  Object? _activeListener;
  final Set<StreamSubscription<ChatResponseChunk>> _backgroundSubscriptions =
      {};
  String? _messageId;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flushTimer;
  ChatMessage? _pendingMessage;

  bool get isActive => _subscription != null;
  String? get messageId => _messageId;

  void listen(
    Stream<ChatResponseChunk> stream, {
    required String messageId,
    required void Function(ChatResponseChunk chunk) onChunk,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) {
    _messageId = messageId;
    final listener = Object();
    _activeListener = listener;
    StreamSubscription<ChatResponseChunk>? subscription;
    subscription = stream.listen(
      onChunk,
      onError: (Object error) {
        if (_activeListener == listener) {
          _subscription = null;
          _activeListener = null;
        }
        _backgroundSubscriptions.remove(subscription);
        onError(error);
      },
      onDone: () {
        if (_activeListener == listener) {
          _subscription = null;
          _activeListener = null;
        }
        _backgroundSubscriptions.remove(subscription);
        onDone();
      },
      cancelOnError: true,
    );
    _subscription = subscription;
  }

  void push(ChatMessage message, {bool force = false}) {
    _pendingMessage = message;
    final now = DateTime.now();
    if (force || now.difference(_lastPush) >= _pushInterval) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _lastPush = now;
      streamingMessage.value = message;
      return;
    }
    _flushTimer ??= Timer(_pushInterval, () {
      _flushTimer = null;
      _lastPush = DateTime.now();
      final pending = _pendingMessage;
      if (pending != null && pending.id == _messageId) {
        streamingMessage.value = pending;
      }
    });
  }

  void sync(void Function(ChatMessage message) upsert) {
    final pending = _pendingMessage ?? streamingMessage.value;
    if (pending != null && pending.id == _messageId) upsert(pending);
  }

  Future<void> cancel() async {
    final subscription = _subscription;
    _subscription = null;
    _activeListener = null;
    await subscription?.cancel();
  }

  /// Keep delivery of client tools for a turn after its thread leaves the UI.
  void detach() {
    final subscription = _subscription;
    if (subscription != null) _backgroundSubscriptions.add(subscription);
    _subscription = null;
    _activeListener = null;
  }

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingMessage = null;
    _messageId = null;
    streamingMessage.value = null;
  }

  void dispose() {
    _subscription?.cancel();
    for (final subscription in _backgroundSubscriptions) {
      subscription.cancel();
    }
    _backgroundSubscriptions.clear();
    _flushTimer?.cancel();
    streamingMessage.dispose();
  }
}
