import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';

/// Manages the Firebase Messaging lifecycle: init, permission, token
/// registration with the backend, and token-refresh handling.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _initialized = false;
  bool _firebaseReady = false;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _registeredToken;

  /// Initialize Firebase and wire up token-refresh handling.
  ///
  /// Safe to call multiple times — only runs once. Silently skips on unsupported
  /// platforms (web/desktop) where google-services.json is not wired up.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[PushService] Firebase init failed: $e');
      return;
    }

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      newToken,
    ) async {
      debugPrint('[PushService] token refreshed');
      await _registerWithBackend(newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        '[PushService] foreground message: ${message.notification?.title}',
      );
    });

    // Handle notification taps when the app is in background/terminated.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      debugPrint('[PushService] notification tapped: $data');
      _handleNotificationTap(data);
    });

    // Handle notification taps that launched the app from terminated state.
    unawaited(
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          debugPrint(
            '[PushService] app launched from notification: ${message.data}',
          );
          _handleNotificationTap(message.data);
        }
      }),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId != null) {
      debugPrint('[PushService] deep-linking to room: $roomId');
      // The navigation is handled by the app's router listening to
      // [PushService.instance.pendingRoomId].
      pendingRoomId = roomId;
      _pendingRoomIdController.add(roomId);
    }
  }

  /// Room ID from a tapped notification, awaiting navigation.
  String? pendingRoomId;

  final StreamController<String> _pendingRoomIdController =
      StreamController<String>.broadcast();
  Stream<String> get onOpenRoom => _pendingRoomIdController.stream;

  /// Request notification permission, fetch the FCM token, and send it to the
  /// backend. Call this after the user successfully logs in.
  Future<void> registerDevice() async {
    if (!_firebaseReady) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[PushService] notification permission denied');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('[PushService] no FCM token available');
        return;
      }

      await _registerWithBackend(token);
    } catch (e) {
      debugPrint('[PushService] registerDevice failed: $e');
    }
  }

  /// Remove the current device token from the backend. Call on logout.
  Future<void> unregisterDevice() async {
    final token = _registeredToken;
    if (token == null) return;
    try {
      await ApiClient.instance.delete(
        '/api/v1/devices/register',
        data: {'token': token, 'platform': _platformString()},
      );
    } catch (e) {
      debugPrint('[PushService] unregisterDevice failed: $e');
    }
    _registeredToken = null;
  }

  Future<void> _registerWithBackend(String token) async {
    try {
      final response = await ApiClient.instance.post(
        '/api/v1/devices/register',
        data: {'token': token, 'platform': _platformString()},
      );
      final ok =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      if (ok) {
        _registeredToken = token;
        debugPrint('[PushService] device registered with backend');
      } else {
        debugPrint(
          '[PushService] backend register failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[PushService] backend register error: $e');
    }
  }

  String _platformString() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _initialized = false;
    _firebaseReady = false;
    _registeredToken = null;
    await _pendingRoomIdController.close();
  }
}
