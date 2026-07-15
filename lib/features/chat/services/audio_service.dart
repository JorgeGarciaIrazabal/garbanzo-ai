import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:garbanzo_ai/core/api_client.dart';

/// A TTS voice available from the backend.
class VoiceOption {
  final String id;
  final String name;
  final String language;

  const VoiceOption({
    required this.id,
    required this.name,
    required this.language,
  });
}

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
  ///
  /// [format] selects the container: `mp3` (default, smaller) or `wav`
  /// (lossless, no encoder priming — avoids a clipped first word on playback).
  Future<Uint8List> speak(
    String text, {
    String voice = 'af_heart',
    double speed = 1.0,
    String format = 'mp3',
  }) async {
    final response = await _api.postBytes(
      '/api/v1/tts/speak',
      data: {
        'text': text,
        'voice': voice,
        'speed': speed,
        'response_format': format,
      },
      receiveTimeout: const Duration(minutes: 3),
    );

    if (response.statusCode == 200 && response.data != null) {
      return Uint8List.fromList(response.data!);
    }

    throw Exception('Speech synthesis failed: ${response.statusCode}');
  }

  /// Fetch the list of available TTS voices from the backend.
  Future<List<VoiceOption>> listVoices() async {
    final response = await _api.get('/api/v1/tts/voices');

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final voices = data['voices'] as List;
      return voices
          .map(
            (v) => VoiceOption(
              id: v['id'] as String,
              name: v['name'] as String,
              language: v['language'] as String,
            ),
          )
          .toList();
    }

    throw Exception('Failed to load voices: ${response.statusCode}');
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
