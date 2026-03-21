import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../../core/api_client.dart';

class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final ApiClient _api = ApiClient.instance;

  /// Transcribe audio bytes to text via the STT backend.
  Future<String> transcribeAudio(Uint8List audioBytes, String filename) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(audioBytes, filename: filename),
    });

    final response = await _api.postMultipart(
      '/api/v1/stt/transcribe',
      data: formData,
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return data['text'] as String;
    }

    throw Exception('Transcription failed: ${response.statusCode}');
  }

  /// Synthesize text to speech audio bytes (non-streaming).
  Future<Uint8List> speak(
    String text, {
    String voice = 'af_heart',
    double speed = 1.0,
  }) async {
    final response = await _api.postBytes(
      '/api/v1/tts/speak',
      data: {
        'text': text,
        'voice': voice,
        'speed': speed,
        'response_format': 'mp3',
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      return Uint8List.fromList(response.data!);
    }

    throw Exception('Speech synthesis failed: ${response.statusCode}');
  }

  /// Stream synthesized speech to a temp file, calling [onReady] with the file
  /// path once the first chunk is written (so playback can start immediately).
  /// Returns the completed file path.
  Future<String> streamSpeak(
    String text, {
    String voice = 'af_heart',
    double speed = 1.0,
    required void Function(String filePath) onReady,
  }) async {
    final response = await _api.postStreamBytes(
      '/api/v1/tts/speak/stream',
      data: {
        'text': text,
        'voice': voice,
        'speed': speed,
        'response_format': 'mp3',
      },
    );

    if (response.statusCode != 200 || response.data == null) {
      throw Exception('Speech stream failed: ${response.statusCode}');
    }

    final dir = Directory.systemTemp;
    final filePath =
        '${dir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final file = File(filePath);
    final sink = file.openWrite();

    bool readyCalled = false;
    try {
      final stream = response.data!.stream;
      await for (final chunk in stream) {
        sink.add(chunk);
        await sink.flush();

        if (!readyCalled) {
          readyCalled = true;
          onReady(filePath);
        }
      }
    } finally {
      await sink.close();
    }

    return filePath;
  }
}
