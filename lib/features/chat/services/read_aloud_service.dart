import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';

const readAloudPath = '/api/v1/tts/read-aloud';

class ReadAloudSegment {
  const ReadAloudSegment({
    required this.id,
    required this.index,
    required this.paragraph,
    required this.startMs,
    required this.durationMs,
  });

  final String id;
  final int index;
  final int paragraph;
  final int startMs;
  final int durationMs;

  factory ReadAloudSegment.fromJson(Map<String, dynamic> data) =>
      ReadAloudSegment(
        id: data['id'] as String,
        index: data['index'] as int,
        paragraph: data['paragraph'] as int,
        startMs: data['start_ms'] as int,
        durationMs: data['duration_ms'] as int,
      );
}

class ReadAloudSession {
  const ReadAloudSession({
    required this.id,
    required this.state,
    required this.generatedDurationMs,
    required this.positionMs,
    required this.totalParagraphs,
    required this.segments,
    this.error,
  });

  final String id;
  final String state;
  final int generatedDurationMs;
  final int positionMs;
  final int totalParagraphs;
  final List<ReadAloudSegment> segments;
  final String? error;

  factory ReadAloudSession.fromJson(Map<String, dynamic> data) =>
      ReadAloudSession(
        id: data['id'] as String,
        state: data['state'] as String,
        generatedDurationMs: data['generated_duration_ms'] as int? ?? 0,
        positionMs: data['position_ms'] as int? ?? 0,
        totalParagraphs: data['total_paragraphs'] as int? ?? 0,
        segments: (data['segments'] as List<dynamic>? ?? const [])
            .map(
              (entry) =>
                  ReadAloudSegment.fromJson(entry as Map<String, dynamic>),
            )
            .toList(growable: false),
        error: data['error'] as String?,
      );
}

class ReadAloudVoice {
  const ReadAloudVoice({
    required this.id,
    required this.name,
    required this.language,
  });
  final String id;
  final String name;
  final String language;

  factory ReadAloudVoice.fromJson(Map<String, dynamic> data) => ReadAloudVoice(
    id: data['id'] as String,
    name: data['name'] as String,
    language: data['language'] as String,
  );
}

class ReadAloudException implements Exception {
  const ReadAloudException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

class ReadAloudService {
  ReadAloudService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  Future<ReadAloudSession> create({
    required String text,
    required String voiceEn,
    required String voiceEs,
    String languageMode = 'auto',
    int startParagraph = 0,
  }) async {
    final response = await _api.post(
      '$readAloudPath/sessions',
      data: {
        'text': text,
        'voice_en': voiceEn,
        'voice_es': voiceEs,
        'language_mode': languageMode,
        if (startParagraph > 0) 'start_paragraph': startParagraph,
      },
    );
    return _session(response, {200, 201, 202});
  }

  Future<ReadAloudSession> status(String id) async =>
      _session(await _api.get('$readAloudPath/sessions/$id'), {200});

  Future<void> update(
    String id,
    String state,
    int positionMs,
    int updateSeq,
  ) async {
    final response = await _api.patch(
      '$readAloudPath/sessions/$id',
      data: {
        'state': state,
        'position_ms': positionMs,
        'update_seq': updateSeq,
      },
    );
    _check(response, {200, 204});
  }

  Future<void> cancel(String id) async {
    final response = await _api.delete('$readAloudPath/sessions/$id');
    _check(response, {200, 204, 404, 410});
  }

  Future<List<ReadAloudVoice>> voices() async {
    final response = await _api.get('$readAloudPath/voices');
    _check(response, {200});
    return ((response.data as Map<String, dynamic>)['voices'] as List<dynamic>)
        .map((item) => ReadAloudVoice.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Emits once per SSE event. Status is read separately so event schema can
  /// evolve without the player interpreting generation internals.
  Stream<void> events(String id) async* {
    final response = await _api.streamGet('$readAloudPath/sessions/$id/events');
    _check(response, {200});
    var pending = '';
    await for (final chunk in response.data!.stream.cast<List<int>>().transform(
      utf8.decoder,
    )) {
      pending += chunk.replaceAll('\r\n', '\n');
      var boundary = pending.indexOf('\n\n');
      while (boundary >= 0) {
        final event = pending.substring(0, boundary);
        pending = pending.substring(boundary + 2);
        if (event.split('\n').any((line) => line.startsWith('data:'))) {
          yield null;
        }
        boundary = pending.indexOf('\n\n');
      }
    }
  }

  Future<({Uri uri, Map<String, String> headers})> audioRequest(
    String id, {
    int startSegment = 0,
  }) async {
    if (kIsWeb) {
      throw const ReadAloudException(
        0,
        'Authenticated read-aloud playback is unavailable in the browser.',
      );
    }
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      throw const ReadAloudException(401, 'Sign in again to listen.');
    }
    final base = _baseUri();
    final uri = base
        .resolve('$readAloudPath/sessions/$id/audio')
        .replace(queryParameters: {'start_segment': '$startSegment'});
    return (
      uri: uri,
      headers: {
        'Authorization': 'Bearer $token',
        if (uri.host.contains('ngrok')) 'ngrok-skip-browser-warning': 'true',
      },
    );
  }

  Future<({Uri uri, Map<String, String> headers})> previewRequest(
    String id,
  ) async {
    if (kIsWeb) {
      throw const ReadAloudException(
        0,
        'Voice previews are unavailable in the browser.',
      );
    }
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      throw const ReadAloudException(401, 'Sign in again to preview voices.');
    }
    final base = _baseUri();
    final uri = base.resolve('$readAloudPath/voices/$id/preview');
    return (
      uri: uri,
      headers: {
        'Authorization': 'Bearer $token',
        if (uri.host.contains('ngrok')) 'ngrok-skip-browser-warning': 'true',
      },
    );
  }

  ReadAloudSession _session(Response response, Set<int> expected) {
    _check(response, expected);
    return ReadAloudSession.fromJson(response.data as Map<String, dynamic>);
  }

  Uri _baseUri() {
    if (_api.baseUrl.isNotEmpty) return Uri.parse(_api.baseUrl);
    if (kIsWeb) return Uri.base;
    throw const ReadAloudException(
      0,
      'The read-aloud server URL is not configured for this app.',
    );
  }

  void _check(Response response, Set<int> expected) {
    if (expected.contains(response.statusCode)) return;
    final body = response.data;
    final detail = body is Map ? body['detail'] : null;
    final message = detail is Map ? detail['message'] : null;
    throw ReadAloudException(
      response.statusCode ?? 0,
      (message is String && message.isNotEmpty ? message : null) ??
          apiErrorDetail(body) ??
          'Read-aloud request failed.',
    );
  }
}
