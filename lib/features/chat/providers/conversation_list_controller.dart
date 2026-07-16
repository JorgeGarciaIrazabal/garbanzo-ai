import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// Owns the sidebar conversation list: loading, pinning, and optimistic
/// delete with an undo window.
///
/// Extracted from [ChatProvider], which composes this controller and forwards
/// its notifications — widgets can keep watching [ChatProvider] alone.
/// Current-conversation and streaming state stay in [ChatProvider].
class ConversationListController extends ChangeNotifier {
  ConversationListController({ChatService? chatService})
    : _chatService = chatService ?? ChatService.instance;

  final ChatService _chatService;

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _chatService.listConversations();
      _conversations = list.items;
    } catch (e) {
      _error = 'Failed to load conversations: $e';
      logDebug(_error!);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Insert a newly created conversation at the top of the list so it shows
  /// in the sidebar before the next full reload.
  void prepend(Conversation conversation) {
    _conversations = [conversation, ..._conversations];
    notifyListeners();
  }

  /// Replace the list entry matching [conversation] (by id), if present.
  void replaceEntry(Conversation conversation) {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      _conversations = [
        ..._conversations.sublist(0, index),
        conversation,
        ..._conversations.sublist(index + 1),
      ];
      notifyListeners();
    }
  }

  /// Toggle the pinned state of a conversation. Returns the updated
  /// conversation so the caller can sync its own copy (e.g. the currently
  /// open conversation), or null when the toggle failed or the id is gone.
  Future<Conversation?> togglePin(String conversationId) async {
    _error = null;
    try {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx < 0) return null;
      final conv = _conversations[idx];
      final updated = await _chatService.updateConversation(
        conversationId,
        isPinned: !conv.isPinned,
      );
      await load();
      return updated;
    } catch (e) {
      _error = 'Failed to pin conversation: $e';
      logDebug(_error!);
      notifyListeners();
      return null;
    }
  }

  /// Mute or unmute a conversation. [duration] is one of `8h`, `1w`,
  /// `forever`, `unmute`. Returns the updated conversation so the caller can
  /// sync its own copy (e.g. the currently open conversation), or null when
  /// the request failed.
  ///
  /// State comes from the server's response rather than being guessed
  /// locally — the backend computes the expiry, so an optimistic write would
  /// have to duplicate that arithmetic and could still drift from the stored
  /// value (mirrors `RoomProvider.setMute`).
  Future<Conversation?> setMute(String conversationId, String duration) async {
    _error = null;
    try {
      final updated = await _chatService.setMute(conversationId, duration);
      replaceEntry(updated);
      return updated;
    } catch (e) {
      _error = 'Failed to update mute: $e';
      logDebug(_error!);
      notifyListeners();
      return null;
    }
  }

  // Deletion is optimistic with an undo window: the conversation leaves the
  // UI immediately, but the API call fires only after the window expires.
  // Undo within the window cancels the deletion entirely.
  static const _undoWindow = Duration(seconds: 6);
  final Map<String, ({Conversation conversation, int index, Timer timer})>
  _pendingDeletes = {};

  /// Remove [conversationId] from the list and schedule the server-side
  /// delete after the undo window. Returns true when the conversation was
  /// present and removed.
  bool delete(String conversationId) {
    _error = null;

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) return false;
    final conversation = _conversations[index];

    _conversations = _conversations
        .where((c) => c.id != conversationId)
        .toList();
    notifyListeners();

    _pendingDeletes.remove(conversationId)?.timer.cancel();
    _pendingDeletes[conversationId] = (
      conversation: conversation,
      index: index,
      timer: Timer(_undoWindow, () => _commitDelete(conversationId)),
    );
    return true;
  }

  /// Restore a conversation deleted within the undo window.
  void undoDelete(String conversationId) {
    final pending = _pendingDeletes.remove(conversationId);
    if (pending == null) return;
    pending.timer.cancel();
    _restore(pending.conversation, pending.index);
  }

  Future<void> _commitDelete(String conversationId) async {
    final pending = _pendingDeletes.remove(conversationId);
    if (pending == null) return;
    try {
      await _chatService.deleteConversation(conversationId);
    } catch (e) {
      // Server-side deletion failed — bring the conversation back.
      _restore(pending.conversation, pending.index);
      _error = 'Failed to delete conversation: $e';
      logDebug(_error!);
    }
  }

  void _restore(Conversation conversation, int index) {
    final list = List<Conversation>.from(_conversations);
    list.insert(index.clamp(0, list.length), conversation);
    _conversations = list;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Flush pending deletions so an undo-window deletion isn't silently
    // dropped when the controller goes away (e.g. logout).
    for (final entry in _pendingDeletes.entries) {
      entry.value.timer.cancel();
      unawaited(_chatService.deleteConversation(entry.key));
    }
    _pendingDeletes.clear();
    super.dispose();
  }
}
