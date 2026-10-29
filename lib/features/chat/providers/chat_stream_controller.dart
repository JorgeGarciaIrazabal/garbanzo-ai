import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/throttled_message_notifier.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

/// Owns the subscription and throttled live-message notifier for one chat turn.
class ChatStreamController {
  final ThrottledMessageNotifier<ChatMessage> _channel =
      ThrottledMessageNotifier<ChatMessage>(idOf: (m) => m.id);

  ValueNotifier<ChatMessage?> get streamingMessage => _channel.notifier;
  StreamSubscription<ChatResponseChunk>? _subscription;
  Object? _activeListener;
  final Set<StreamSubscription<ChatResponseChunk>> _backgroundSubscriptions =
      {};

  bool get isActive => _subscription != null;
  String? get messageId => _channel.messageId;

  void listen(
    Stream<ChatResponseChunk> stream, {
    required String messageId,
    required void Function(ChatResponseChunk chunk) onChunk,
    required void Function(Object error) onError,
    required void Function() onDone,
  }) {
    _channel.messageId = messageId;
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

  void push(ChatMessage message, {bool force = false}) =>
      _channel.push(message, force: force);

  void sync(void Function(ChatMessage message) upsert) => _channel.sync(upsert);

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

  void clear() => _channel.clear();

  void dispose() {
    _subscription?.cancel();
    for (final subscription in _backgroundSubscriptions) {
      subscription.cancel();
    }
    _backgroundSubscriptions.clear();
    _channel.dispose();
  }
}
