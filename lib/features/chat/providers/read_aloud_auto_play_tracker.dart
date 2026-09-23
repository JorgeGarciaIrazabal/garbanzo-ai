import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

/// Waits for a completed reply's persisted ID before starting auto-play.
/// Streaming messages use temporary IDs, and the action row is mounted only
/// after the stream ends, so a button lifecycle callback cannot own this.
class ReadAloudAutoPlayTracker {
  bool _wasSending = false;
  String? _sendingConversationId;
  String? _baselineReplyId;
  String? _pendingConversationId;
  String? _pendingText;
  String? _pendingBaselineReplyId;
  Stopwatch? _pendingAge;

  void reset({
    bool sending = false,
    String? conversationId,
    List<ChatMessage> messages = const [],
  }) {
    _wasSending = sending;
    _sendingConversationId = sending ? conversationId : null;
    _baselineReplyId = sending ? _latestStableReply(messages)?.id : null;
    _clearPending();
  }

  ChatMessage? observe({
    required bool sending,
    required String? conversationId,
    required List<ChatMessage> messages,
    required bool hasError,
  }) {
    if (sending) {
      if (!_wasSending || _sendingConversationId != conversationId) {
        _sendingConversationId = conversationId;
        _baselineReplyId = _latestStableReply(messages)?.id;
      }
      _wasSending = true;
      _clearPending();
      return null;
    }

    if (_wasSending) {
      _wasSending = false;
      if (!hasError &&
          conversationId != null &&
          conversationId == _sendingConversationId) {
        final latest = _latestReply(messages);
        if (latest != null &&
            latest.id != _baselineReplyId &&
            latest.metadata?['stopped'] != true) {
          final text = visibleAssistantContent(latest.content);
          if (text.isNotEmpty) {
            _pendingConversationId = conversationId;
            _pendingText = text;
            _pendingBaselineReplyId = _baselineReplyId;
            _pendingAge = Stopwatch()..start();
          }
        }
      }
      _sendingConversationId = null;
      _baselineReplyId = null;
    }

    if (hasError ||
        _pendingConversationId != conversationId ||
        (_pendingAge?.elapsed ?? Duration.zero) > const Duration(seconds: 30)) {
      _clearPending();
      return null;
    }
    final pendingText = _pendingText;
    if (pendingText == null) return null;
    final latest = _latestReply(messages);
    if (latest == null ||
        latest.id.startsWith('temp-') ||
        latest.id == _pendingBaselineReplyId ||
        visibleAssistantContent(latest.content) != pendingText) {
      return null;
    }
    _clearPending();
    return latest;
  }

  void _clearPending() {
    _pendingConversationId = null;
    _pendingText = null;
    _pendingBaselineReplyId = null;
    _pendingAge = null;
  }

  static ChatMessage? _latestReply(List<ChatMessage> messages) => messages
      .where(
        (message) =>
            message.isAssistant && !message.isToolCall && !message.isToolResult,
      )
      .lastOrNull;

  static ChatMessage? _latestStableReply(List<ChatMessage> messages) => messages
      .where(
        (message) =>
            message.isAssistant &&
            !message.isToolCall &&
            !message.isToolResult &&
            !message.id.startsWith('temp-'),
      )
      .lastOrNull;
}

String visibleAssistantContent(String raw) {
  if (raw.contains('</think>')) {
    final parts = raw.split('</think>');
    return parts.length > 1 ? parts.sublist(1).join('</think>').trim() : '';
  }
  return raw;
}
