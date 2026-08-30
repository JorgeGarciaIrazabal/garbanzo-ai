import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/guarded_state.dart';

/// The DioException shape produced by dio's IO adapter when the server closes
/// the socket before headers complete ("Connection closed before full header
/// was received" — the exact error behind a wave of user reports).
DioException _connectionClosedError() {
  final options = RequestOptions(path: '/api/v1/chat/conversations/1/chat');
  return DioException.connectionError(
    requestOptions: options,
    reason: 'Connection closed before full header was received',
  );
}

void main() {
  group('isTransportFailure', () {
    test('classifies dio connection errors as transport failures', () {
      expect(isTransportFailure(_connectionClosedError()), isTrue);
    });

    test('classifies connection timeouts as transport failures', () {
      final e = DioException.connectionTimeout(
        requestOptions: RequestOptions(path: '/x'),
        timeout: const Duration(seconds: 30),
      );
      expect(isTransportFailure(e), isTrue);
    });

    test('classifies unknown-typed socket errors as transport failures', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.unknown,
        error: 'SocketException: Network is unreachable',
      );
      expect(isTransportFailure(e), isTrue);
    });

    test('does not classify HTTP responses as transport failures', () {
      final options = RequestOptions(path: '/x');
      final e = DioException.badResponse(
        statusCode: 500,
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 500),
      );
      expect(isTransportFailure(e), isFalse);
    });
  });

  group('isGatewayFailure', () {
    test('detects the ngrok ERR_NGROK_3004 503 from user reports', () {
      // Body from the real report e8b8cc0f: plain text, not FastAPI JSON.
      const body = 'ngrok gateway error\r\n'
          'The server returned an invalid or incomplete HTTP response.\r\n'
          '\r\n'
          'ERR_NGROK_3004';
      expect(isGatewayFailure(503, body: body), isTrue);
    });

    test('detects generic nginx/Cloudflare gateway pages', () {
      expect(isGatewayFailure(502, body: '<html>502 Bad Gateway</html>'),
          isTrue);
      expect(isGatewayFailure(503, body: 'cloudflare error page'), isTrue);
      expect(isGatewayFailure(504, body: 'Gateway Timeout'), isTrue);
    });

    test('a JSON 503 from the backend itself is NOT a gateway failure', () {
      expect(
        isGatewayFailure(503, body: {'detail': 'Ollama is not reachable'}),
        isFalse,
      );
    });

    test('non-gateway statuses never classify as gateway failures', () {
      expect(isGatewayFailure(500, body: 'ngrok'), isFalse);
      expect(isGatewayFailure(404, body: '<html>not found</html>'), isFalse);
    });
  });

  group('ApiClient.shouldReportError', () {
    test('does NOT report transport failures (connection closed)', () {
      expect(ApiClient.shouldReportError(_connectionClosedError()), isFalse);
    });

    test('does NOT report network-unreachable socket errors', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/api/v1/chat/conversations'),
        type: DioExceptionType.unknown,
        error: 'SocketException: Network is unreachable',
      );
      expect(ApiClient.shouldReportError(e), isFalse);
    });

    test('does NOT report a cancelled request', () {
      final e = DioException.requestCancelled(
        requestOptions: RequestOptions(path: '/x'),
        reason: 'client closed connection',
      );
      expect(ApiClient.shouldReportError(e), isFalse);
    });

    test('does NOT report a 503 ngrok gateway page', () {
      final options = RequestOptions(path: '/api/v1/rooms/1/agents');
      final e = DioException.badResponse(
        statusCode: 503,
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 503,
          data: 'ngrok gateway error\nERR_NGROK_3004',
        ),
      );
      expect(ApiClient.shouldReportError(e), isFalse);
    });

    test('reports a genuine backend 500', () {
      final options = RequestOptions(path: '/api/v1/chat/conversations');
      final e = DioException.badResponse(
        statusCode: 500,
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 500,
          data: {'detail': 'Internal Server Error'},
        ),
      );
      expect(ApiClient.shouldReportError(e), isTrue);
    });

    test('reports a JSON 503 raised through the error path', () {
      final options = RequestOptions(path: '/api/v1/stt/transcribe');
      final e = DioException.badResponse(
        statusCode: 503,
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 503,
          data: {'detail': 'STT service unavailable'},
        ),
      );
      expect(ApiClient.shouldReportError(e), isTrue);
    });
  });

  group('ApiClient.shouldReportResponse', () {
    Response buildResponse(int status, Object? data,
        {ResponseType responseType = ResponseType.json}) {
      final options = RequestOptions(
        path: '/api/v1/things',
        responseType: responseType,
      );
      return Response(requestOptions: options, statusCode: status, data: data);
    }

    test('does NOT report a ngrok 503 gateway page', () {
      expect(
        ApiClient.shouldReportResponse(
          buildResponse(503, 'ngrok gateway error ERR_NGROK_3004'),
        ),
        isFalse,
      );
    });

    test('reports a JSON 500 from the backend', () {
      expect(
        ApiClient.shouldReportResponse(
          buildResponse(500, {'detail': 'boom'}),
        ),
        isTrue,
      );
    });

    test('does NOT report a 4xx', () {
      expect(ApiClient.shouldReportResponse(buildResponse(404, null)), isFalse);
    });

    test('does NOT report stream responses (callers handle them)', () {
      expect(
        ApiClient.shouldReportResponse(
          buildResponse(500, {'detail': 'boom'}, responseType: ResponseType.stream),
        ),
        isFalse,
      );
    });
  });
}