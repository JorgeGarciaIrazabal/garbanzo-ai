import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../services/notification_api_service.dart';

/// Provider for the in-app notification center.
///
/// Holds the list of notifications plus an unread count badge. Polls the
/// backend periodically while the app is in the foreground so the badge stays
/// roughly current without pushing new state over FCM to the Flutter side.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider() {
    refresh();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnreadCount(),
    );
  }

  final NotificationApiService _api = NotificationApiService.instance;
  Timer? _pollTimer;

  List<AppNotification> _items = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;

  NotificationPreferences? _preferences;
  bool _loadingPreferences = false;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;
  NotificationPreferences? get preferences => _preferences;
  bool get loadingPreferences => _loadingPreferences;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _api.list();
      _items = result.items;
      _unreadCount = result.unreadCount;
    } catch (e) {
      _error = 'Failed to load notifications: $e';
      if (kDebugMode) debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final count = await _api.unreadCount();
      if (count != _unreadCount) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (_) {
      // Silent — poll error shouldn't spam the UI.
    }
  }

  Future<void> markRead(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    if (_items[idx].isRead) return;
    _items = [
      ..._items.sublist(0, idx),
      _items[idx].copyWith(isRead: true),
      ..._items.sublist(idx + 1),
    ];
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await _api.markRead(id);
    } catch (e) {
      if (kDebugMode) debugPrint('markRead failed: $e');
    }
  }

  Future<void> markAllRead() async {
    if (_unreadCount == 0) return;
    _items = _items.map((n) => n.copyWith(isRead: true)).toList();
    _unreadCount = 0;
    notifyListeners();
    try {
      await _api.markAllRead();
    } catch (e) {
      if (kDebugMode) debugPrint('markAllRead failed: $e');
    }
  }

  Future<void> remove(String id) async {
    _items = _items.where((n) => n.id != id).toList();
    notifyListeners();
    try {
      await _api.delete(id);
      await _refreshUnreadCount();
    } catch (e) {
      if (kDebugMode) debugPrint('delete failed: $e');
    }
  }

  // ---- preferences ----

  Future<void> loadPreferences() async {
    if (_loadingPreferences) return;
    _loadingPreferences = true;
    notifyListeners();
    try {
      _preferences = await _api.getPreferences();
    } catch (e) {
      if (kDebugMode) debugPrint('loadPreferences failed: $e');
    } finally {
      _loadingPreferences = false;
      notifyListeners();
    }
  }

  Future<void> updatePreferences({
    bool? chatResponsesEnabled,
    bool? remindersEnabled,
    bool? systemAlertsEnabled,
  }) async {
    final current = _preferences;
    if (current == null) await loadPreferences();

    // Optimistic update
    if (_preferences != null) {
      _preferences = _preferences!.copyWith(
        chatResponsesEnabled: chatResponsesEnabled,
        remindersEnabled: remindersEnabled,
        systemAlertsEnabled: systemAlertsEnabled,
      );
      notifyListeners();
    }

    try {
      _preferences = await _api.updatePreferences(
        chatResponsesEnabled: chatResponsesEnabled,
        remindersEnabled: remindersEnabled,
        systemAlertsEnabled: systemAlertsEnabled,
      );
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('updatePreferences failed: $e');
      await loadPreferences();
    }
  }
}
