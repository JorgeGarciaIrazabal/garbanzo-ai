import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/tts_audio_source.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android MP3 TTS uses a seekable file source and removes it on dispose',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final prepared = await prepareTtsAudioSource(
        Uint8List.fromList([1, 2, 3]),
        format: 'mp3',
      );

      expect(prepared.source, isA<DeviceFileSource>());
      final path = (prepared.source as DeviceFileSource).path;
      expect(path, endsWith('.mp3'));
      expect(await File(path).readAsBytes(), [1, 2, 3]);

      await prepared.dispose();
      expect(await File(path).exists(), isFalse);
    },
  );

  test(
    'non-Android TTS keeps in-memory bytes with an explicit MIME type',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final prepared = await prepareTtsAudioSource(
        Uint8List.fromList([4, 5, 6]),
        format: 'mp3',
      );

      expect(prepared.source, isA<BytesSource>());
      final source = prepared.source as BytesSource;
      expect(source.bytes, [4, 5, 6]);
      expect(source.mimeType, 'audio/mpeg');
    },
  );
}
