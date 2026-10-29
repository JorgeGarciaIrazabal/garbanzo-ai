import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/memory/services/memory_api_service.dart';

class _MockApiClient extends Mock implements ApiClient {}

Response<dynamic> _response(int statusCode, dynamic data) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/api/v1/test'),
  statusCode: statusCode,
  data: data,
);

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

  group('expectStatus and apiResponseError', () {
    test('expectStatus returns silently when status is in expected set', () {
      expect(
        () => expectStatus(_response(201, {'id': '1'}), const {
          200,
          201,
        }, operation: 'Failed to create item'),
        returnsNormally,
      );
    });

    test('expectStatus throws ApiResponseException with FastAPI 422 list', () {
      expect(
        () => expectStatus(
          _response(422, {
            'detail': [
              {
                'loc': ['body', 'content'],
                'msg': 'String should have at least 1 character',
              },
            ],
          }),
          const {201},
          operation: 'Failed to create memory',
        ),
        throwsA(
          isA<ApiResponseException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.detail,
                'detail',
                'String should have at least 1 character',
              ),
        ),
      );
    });

    test(
      'service with injected ApiClient parses 422 validation list safely',
      () async {
        final api = _MockApiClient();
        when(
          () => api.post('/api/v1/memories', data: any(named: 'data')),
        ).thenAnswer(
          (_) async => _response(422, {
            'detail': [
              {
                'loc': ['body', 'content'],
                'msg': 'Field required',
              },
            ],
          }),
        );

        final service = MemoryApiService(api: api);

        await expectLater(
          service.createMemory(content: ''),
          throwsA(
            isA<ApiResponseException>()
                .having((e) => e.statusCode, 'statusCode', 422)
                .having((e) => e.detail, 'detail', 'Field required'),
          ),
        );
      },
    );
  });
}
