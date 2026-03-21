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

  /// Synthesize text to speech audio bytes.
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
}
