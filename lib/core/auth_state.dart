import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/notifications/services/push_service.dart';

/// App-wide authentication state.
///
/// Owns the logged-in flag the router's redirect guard reads, and the side
/// effects of session changes (device push registration, current-user cache
/// warm-up). Replaces the old `AuthGate` widget and the `onLogout` /
/// `onLoginSuccess` callbacks that were threaded through the page tree.
class AuthState extends ChangeNotifier {
  bool _ready = false;
  bool _loggedIn = false;
  int _epoch = 0;
  Future<void>? _initFuture;

  /// Whether the initial token check has completed.
  bool get ready => _ready;

  bool get loggedIn => _loggedIn;

  /// Increments on logout. The app-level provider subtree is keyed on this so
  /// all user-scoped state (conversations, notifications, …) is disposed and
  /// rebuilt fresh on the next login.
  int get epoch => _epoch;

  /// Completes once the stored token has been validated against the backend.
  /// Idempotent — the check runs once and is cached.
  Future<void> ensureReady() => _initFuture ??= _init();

  Future<void> _init() async {
    _loggedIn = await AuthService.instance.isLoggedIn();
    _ready = true;
    if (_loggedIn) {
      unawaited(PushService.instance.registerDevice());
      unawaited(AuthService.instance.syncDeviceContext());
    }
    notifyListeners();
  }

  /// Called by the login page after a successful login.
  void markLoggedIn() {
    _loggedIn = true;
    _ready = true;
    // Fire-and-forget: populate cached user (including is_admin) without
    // blocking the UI transition, then report the device timezone/locale
    // (syncDeviceContext reuses the just-cached user, so no double fetch).
    unawaited(
      AuthService.instance.getCurrentUser().then(
        (_) => AuthService.instance.syncDeviceContext(),
      ),
    );
    unawaited(PushService.instance.registerDevice());
    // If a push notification was tapped while logged out, navigate now.
    final pending = PushService.instance.pendingRoute;
    if (pending != null) {
      PushService.instance.pendingRoute = null;
      // Defer to next frame so the router's redirect guard has processed
      // the loggedIn state change before we push the route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingRouteNavigator?.call(pending);
      });
    }
    notifyListeners();
  }

  /// Callback set by the app state to navigate to a pending route after login.
  void Function(String)? _pendingRouteNavigator;
  set pendingRouteNavigator(void Function(String)? fn) =>
      _pendingRouteNavigator = fn;

  Future<void> logout() async {
    unawaited(PushService.instance.unregisterDevice());
    await AuthService.instance.logout();
    _loggedIn = false;
    _epoch++;
    notifyListeners();
  }
}
