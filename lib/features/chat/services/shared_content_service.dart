import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:garbanzo_ai/core/log.dart';

/// A file received from another app through Android's share sheet.
class SharedFile {
  const SharedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Content supplied by one Android ACTION_SEND or ACTION_SEND_MULTIPLE intent.
class SharedContent {
  const SharedContent({required this.files, this.text});

  final List<SharedFile> files;
  final String? text;

  bool get isEmpty => files.isEmpty && (text == null || text!.trim().isEmpty);

  factory SharedContent.fromPlatform(Object? value) {
    if (value is! Map) return const SharedContent(files: []);

    final files = <SharedFile>[];
    final rawFiles = value['files'];
    if (rawFiles is List) {
      for (final rawFile in rawFiles) {
        if (rawFile is! Map) continue;
        final name = rawFile['name'];
        final rawBytes = rawFile['bytes'];
        final bytes = switch (rawBytes) {
          final Uint8List value => value,
          final List<int> value => Uint8List.fromList(value),
          _ => null,
        };
        if (name is String && name.isNotEmpty && bytes != null) {
          files.add(SharedFile(name: name, bytes: bytes));
        }
      }
    }

    final rawText = value['text'];
    return SharedContent(
      files: files,
      text: rawText is String ? rawText : null,
    );
  }
}

/// Receives Android share intents and keeps them queued until the chat composer
/// is mounted. Other platforms intentionally no-op.
class SharedContentService {
  SharedContentService._();

  static final instance = SharedContentService._();
  static const _channel = MethodChannel(
    'com.example.garbanzo_ai/shared_content',
  );

  final _pending = <SharedContent>[];
  final _incoming = StreamController<SharedContent>.broadcast();
  bool _started = false;

  Stream<SharedContent> get incoming => _incoming.stream;

  Future<void> start() async {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedContent') _enqueue(call.arguments);
    });

    try {
      _enqueue(await _channel.invokeMethod<Object?>('getInitialShare'));
    } on MissingPluginException {
      // Expected in unit tests and on embeddings without the Android bridge.
    } on PlatformException catch (error) {
      logDebug('Could not receive shared Android content: $error');
    }
  }

  List<SharedContent> takePending() {
    final result = List<SharedContent>.from(_pending);
    _pending.clear();
    return result;
  }

  void _enqueue(Object? value) {
    final content = SharedContent.fromPlatform(value);
    if (content.isEmpty) return;
    _pending.add(content);
    _incoming.add(content);
  }
}
