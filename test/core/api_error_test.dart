import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/api_error.dart';

void main() {
  group('apiErrorDetail', () {
    test('extracts a FastAPI detail string', () {
      expect(
        apiErrorDetail({'detail': 'STT service unavailable'}),
        'STT service unavailable',
      );
    });

    test('extracts the first FastAPI validation message', () {
      expect(
        apiErrorDetail({
          'detail': [
            {
              'loc': ['body', 'file'],
              'msg': 'Field required',
            },
          ],
        }),
        'Field required',
      );
    });

    test('returns null for an unrecognized body', () {
      expect(apiErrorDetail({'unexpected': true}), isNull);
    });
  });

  test('ApiResponseException retains status and detail', () {
    const error = ApiResponseException(
      statusCode: 502,
      operation: 'Transcription failed',
      detail: 'STT service unavailable',
    );

    expect('$error', 'API Error (502): STT service unavailable');
  });
}
