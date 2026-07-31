import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/guarded_state.dart';

DioException _dio(DioExceptionType type, {Object? error, String? message}) {
  return DioException(
    requestOptions: RequestOptions(path: '/api/v1/thing'),
    type: type,
    error: error,
    message: message,
  );
}

/// Minimal concrete provider that exposes [runGuarded] for testing.
class _TestProvider extends ChangeNotifier with GuardedStateMixin {
  int notifyCount = 0;

  _TestProvider() {
    addListener(() => notifyCount++);
  }

  Future<int?> run(Future<int> Function() fn, {bool trackLoading = true}) {
    return runGuarded('Failed to do the thing', fn, trackLoading: trackLoading);
  }
}

void main() {
  group('describeFailure - transport failures', () {
    test('connection error → generic unreachable message', () {
      expect(
        describeFailure(_dio(DioExceptionType.connectionError)),
        "Can't reach the server. Check your connection.",
      );
    });

    test('connection timeout → unreachable message', () {
      expect(
        describeFailure(_dio(DioExceptionType.connectionTimeout)),
        "Can't reach the server. Check your connection.",
      );
    });

    test('receive/send timeout → unreachable message', () {
      expect(
        describeFailure(_dio(DioExceptionType.receiveTimeout)),
        "Can't reach the server. Check your connection.",
      );
      expect(
        describeFailure(_dio(DioExceptionType.sendTimeout)),
        "Can't reach the server. Check your connection.",
      );
    });

    test('unknown DioException wrapping a socket/DNS error → unreachable', () {
      expect(
        describeFailure(
          _dio(
            DioExceptionType.unknown,
            message: 'SocketException: Failed host lookup',
          ),
        ),
        "Can't reach the server. Check your connection.",
      );
    });
  });

  group('describeFailure - HTTP status mapping', () {
    test('401 → session expired by default', () {
      expect(
        describeFailure(Exception('API Error (401): token expired')),
        'Session expired. Please log in again.',
      );
    });

    test('401 → custom unauthorized message when provided', () {
      expect(
        describeFailure(
          Exception('API Error (401): bad creds'),
          unauthorizedMessage: 'Incorrect email or password',
        ),
        'Incorrect email or password',
      );
    });

    test('403 → permission message', () {
      expect(
        describeFailure(Exception('API Error (403): forbidden')),
        "You don't have permission to do that.",
      );
    });

    test('500 → server error message', () {
      expect(
        describeFailure(Exception('API Error (500): boom')),
        'Server error — please try again.',
      );
    });

    test('500 with an action label keeps the message contextual', () {
      expect(
        describeFailure(
          Exception('API Error (502): Library libcublas.so.12 is missing'),
          label: 'Could not transcribe',
          contextualServerError: true,
        ),
        'Could not transcribe — please try again.',
      );
    });

    test('503 via "HTTP NNN" form → server error message', () {
      expect(
        describeFailure(Exception('Failed to load usage: HTTP 503')),
        'Server error — please try again.',
      );
    });

    test('4xx with a concise server detail surfaces the detail', () {
      expect(
        describeFailure(
          Exception('API Error (400): Email already registered'),
          label: 'Failed to register',
        ),
        'Failed to register: Email already registered',
      );
    });

    test('4xx with no detail falls back to label', () {
      expect(
        describeFailure(
          Exception('Failed to delete template (404)'),
          label: 'Failed to delete template',
        ),
        'Failed to delete template. Please try again.',
      );
    });

    test('DioException carrying a response status code is mapped', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 403,
        ),
      );
      expect(describeFailure(e), "You don't have permission to do that.");
    });
  });

  group('describeFailure - unclassified', () {
    test('unknown error with label → label + retry', () {
      expect(
        describeFailure(Exception('weird'), label: 'Failed to load memories'),
        'Failed to load memories. Please try again.',
      );
    });

    test('unknown error without label → generic', () {
      expect(
        describeFailure(Exception('weird')),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('runGuarded', () {
    test('toggles isLoading and returns the value on success', () async {
      final p = _TestProvider();
      final states = <bool>[];
      p.addListener(() => states.add(p.isLoading));

      final result = await p.run(() async => 42);

      expect(result, 42);
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);
      // Saw loading=true at start and loading=false at end.
      expect(states.first, isTrue);
      expect(states.last, isFalse);
    });

    test('sets a mapped error and returns null on throw', () async {
      final p = _TestProvider();

      final result = await p.run(
        () async => throw Exception('API Error (500): boom'),
      );

      expect(result, isNull);
      expect(p.error, 'Server error — please try again.');
      expect(p.isLoading, isFalse);
      // Raw error retained for debugging, not shown to the user.
      expect(p.lastErrorDetail, contains('boom'));
    });

    test('clears a previous error on the next successful run', () async {
      final p = _TestProvider();

      await p.run(() async => throw Exception('API Error (403): nope'));
      expect(p.error, isNotNull);

      await p.run(() async => 1);
      expect(p.error, isNull);
      expect(p.lastErrorDetail, isNull);
    });

    test('trackLoading:false never flips isLoading', () async {
      final p = _TestProvider();
      final seen = <bool>[];
      p.addListener(() => seen.add(p.isLoading));

      await p.run(() async => 7, trackLoading: false);

      expect(seen.every((v) => v == false), isTrue);
      expect(p.isLoading, isFalse);
    });

    test('clearError resets error and detail and notifies', () async {
      final p = _TestProvider();
      await p.run(() async => throw Exception('API Error (401): x'));
      expect(p.error, isNotNull);

      final before = p.notifyCount;
      p.clearError();
      expect(p.error, isNull);
      expect(p.lastErrorDetail, isNull);
      expect(p.notifyCount, greaterThan(before));
    });

    test('clearError is a no-op (no notify) when there is no error', () {
      final p = _TestProvider();
      final before = p.notifyCount;
      p.clearError();
      expect(p.notifyCount, before);
    });
  });
}
