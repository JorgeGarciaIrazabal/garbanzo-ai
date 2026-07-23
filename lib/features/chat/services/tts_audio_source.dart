import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// An audio source prepared for reliable TTS playback on the current platform.
///
/// Android's MediaPlayer-backed BytesSource can fail during preparation with
/// MEDIA_ERROR_SYSTEM. A real file with the container extension gives the
/// platform extractor a seekable source and avoids that failure mode.
class PreparedTtsAudioSource {
  PreparedTtsAudioSource(this.source, [this._temporaryDirectory]);

  final Source source;
  final Directory? _temporaryDirectory;

  Future<void> dispose() async {
    final directory = _temporaryDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<PreparedTtsAudioSource> prepareTtsAudioSource(
  Uint8List bytes, {
  required String format,
}) async {
  final normalizedFormat = format.toLowerCase();
  final mimeType = switch (normalizedFormat) {
    'wav' => 'audio/wav',
    _ => 'audio/mpeg',
  };

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final directory = await Directory.systemTemp.createTemp('garbanzo_tts_');
    final file = File('${directory.path}/speech.$normalizedFormat');
    await file.writeAsBytes(bytes, flush: true);
    return PreparedTtsAudioSource(
      DeviceFileSource(file.path, mimeType: mimeType),
      directory,
    );
  }

  return PreparedTtsAudioSource(BytesSource(bytes, mimeType: mimeType));
}
