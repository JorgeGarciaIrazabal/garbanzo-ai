import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/log.dart';

/// Default user-facing message shown when a request fails with 401.
///
/// Login/register override this (see [describeFailure]) so an unauthorized
/// result reads as "wrong credentials" rather than "session expired".
const String kSessionExpiredMessage = 'Session expired. Please log in again.';

/// Translates a raw error thrown by a service/HTTP call into a short,
/// user-facing message. Never dumps a raw [DioException] or stack-y exception
/// text into the UI.
///
/// The app's [ApiClient] disables Dio status validation, so failed HTTP
/// responses do NOT surface as [DioException]s — services instead throw plain
/// `Exception`s whose message embeds the status code, e.g.
/// `"API Error (404): Not found"` or `"Failed to load usage: HTTP 500"`.
/// [DioException]s therefore almost always mean a transport-level problem
/// (connection refused, DNS failure, timeout).
///
/// - [label] is an optional short action description (e.g.
///   `"Failed to load memories"`) used to build a fallback message for
///   otherwise-unclassified failures.
/// - [unauthorizedMessage] is the copy used for a 401. Defaults to
///   [kSessionExpiredMessage]; auth screens pass
///   `"Incorrect email or password"`.
String describeFailure(
  Object error, {
  String? label,
  String unauthorizedMessage = kSessionExpiredMessage,
  bool contextualServerError = false,
}) {
  // Transport-level failures (no HTTP response reached us).
  if (error is DioException && isTransportFailure(error)) {
    return "Can't reach the server. Check your connection.";
  }

  final status = _statusCodeOf(error);
  if (status != null) {
    if (status == 401) return unauthorizedMessage;
    if (status == 403) return "You don't have permission to do that.";
    if (status >= 500) {
      return contextualServerError && label != null
          ? '$label — please try again.'
          : 'Server error — please try again.';
    }
    // Other client errors (400/404/409/422…): prefer a concise server-provided
    // reason if there is one, otherwise fall back to the label.
    final detail = _serverDetail(error);
    if (detail != null) {
      return label != null ? '$label: $detail' : detail;
    }
  }

  if (label != null) return '$label. Please try again.';
  return 'Something went wrong. Please try again.';
}

/// Whether [e] represents a transport failure (connection/DNS/timeout) rather
/// than an HTTP response with a status code.
bool isTransportFailure(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return true;
    case DioExceptionType.unknown:
      // Dio wraps socket/DNS errors as `unknown`. Detect them by message so we
      // don't need dart:io (unavailable on web).
      final text = '${e.error ?? e.message ?? ''}'.toLowerCase();
      return text.contains('socketexception') ||
          text.contains('failed host lookup') ||
          text.contains('connection refused') ||
          text.contains('connection closed') ||
          text.contains('network is unreachable') ||
          text.contains('clientexception');
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;
    default:
      // Newer Dio versions may add types (e.g. transformTimeout); treat
      // anything unrecognized as non-transport so it maps to a generic message.
      return false;
  }
}

/// Whether a 502/503/504 response body looks like it came from a reverse
/// proxy or tunnel (ngrok, Cloudflare, nginx…) rather than the backend itself.
///
/// Gateway error pages are plain text/HTML with telltale markers; the backend's
/// own 5xx bodies are JSON (FastAPI `{"detail": …}`). Used to keep transient
/// infrastructure hiccups from being auto-filed as app bug reports while still
/// reporting genuine backend errors.
bool isGatewayFailure(int status, {Object? body}) {
  if (status != 502 && status != 503 && status != 504) return false;
  if (body is Map) return false; // JSON → the backend answered itself
  final text = '$body'.toLowerCase();
  return text.contains('ngrok') ||
      text.contains('bad gateway') ||
      text.contains('gateway error') ||
      text.contains('gateway timeout') ||
      text.contains('502 bad gateway') ||
      text.contains('504 gateway') ||
      text.contains('cloudflare') ||
      text.contains('<html');
}

/// Extracts an HTTP status code from [error] if one is discernible, either from
/// a [DioException] response or from the embedded `(NNN)` / `HTTP NNN` marker in
/// a service-thrown exception message.
int? _statusCodeOf(Object error) {
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code != null) return code;
  }
  final text = error.toString();
  final paren = RegExp(r'\((\d{3})\)').firstMatch(text);
  if (paren != null) return int.tryParse(paren.group(1)!);
  final http = RegExp(r'HTTP\s+(\d{3})').firstMatch(text);
  if (http != null) return int.tryParse(http.group(1)!);
  return null;
}

/// Pulls a short human-readable reason out of a service exception of the form
/// `"API Error (400): <detail>"`, if present and reasonably concise.
String? _serverDetail(Object error) {
  final match = RegExp(
    r'API Error \(\d{3}\):\s*(.+)$',
  ).firstMatch(error.toString());
  if (match == null) return null;
  final detail = match.group(1)!.trim();
  if (detail.isEmpty || detail.length > 200) return null;
  return detail;
}

/// Mixin for [ChangeNotifier] providers that removes the copy-pasted
/// `String? _error` / `bool _isLoading` / `catch (e) { _error = '…$e'; … }`
/// boilerplate. Wrap an async operation in [runGuarded] and it will manage the
/// loading flag, map failures to a user-facing [error] message, retain the raw
/// error in [lastErrorDetail] for debugging, and notify listeners.
mixin GuardedStateMixin on ChangeNotifier {
  String? _error;

  /// User-facing error message from the most recent guarded operation, or null.
  String? get error => _error;

  Object? _lastError;

  /// The raw error object behind [error], stringified, for debugging/logging.
  /// Not intended for display.
  String? get lastErrorDetail => _lastError?.toString();

  bool _isLoading = false;

  /// Whether a guarded operation (with `trackLoading`) is in flight.
  bool get isLoading => _isLoading;

  /// Clear any current [error] and notify listeners (only if something changed).
  void clearError() {
    if (_error == null && _lastError == null) return;
    _error = null;
    _lastError = null;
    notifyListeners();
  }

  /// Set a user-facing error directly (e.g. for validation) plus optional raw
  /// [detail]. Notifies listeners.
  @protected
  void setError(String message, [Object? detail]) {
    _error = message;
    _lastError = detail;
    notifyListeners();
  }

  /// Run [fn], catching any failure. On success returns its value; on failure
  /// sets [error] to a mapped, user-facing message (built with [label]), logs
  /// the raw error, and returns null.
  ///
  /// When [trackLoading] is true (default), [isLoading] is set for the duration
  /// of the call. Listeners are notified at the start (when loading toggles or a
  /// prior error is cleared) and always at the end.
  @protected
  Future<T?> runGuarded<T>(
    String label,
    Future<T> Function() fn, {
    bool trackLoading = true,
  }) async {
    final hadError = _error != null || _lastError != null;
    _error = null;
    _lastError = null;
    if (trackLoading) _isLoading = true;
    if (trackLoading || hadError) notifyListeners();

    try {
      return await fn();
    } catch (e) {
      _error = describeFailure(e, label: label);
      _lastError = e;
      logDebug('$label failed: $e');
      return null;
    } finally {
      if (trackLoading) _isLoading = false;
      notifyListeners();
    }
  }
}
