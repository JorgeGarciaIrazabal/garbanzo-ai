import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';

/// Result of a file picking operation.
class FilePickResult {
  const FilePickResult({
    required this.added,
    required this.rejected,
    required this.validationErrors,
  });

  final List<ChatAttachment> added;
  final List<String> rejected;
  final List<String> validationErrors;
}

/// A raw file (name + bytes) awaiting validation. Used by callers that get
/// files from somewhere other than the picker (e.g. drag-and-drop).
typedef RawPickedFile = ({String name, Uint8List bytes});

typedef _ImageFitInput = ({
  String name,
  String mimeType,
  Uint8List bytes,
  int limitBytes,
});
typedef _ImageFitOutput = ({String name, String mimeType, Uint8List bytes});

const _maxImageBytes = 3 * 1024 * 1024;

_ImageFitOutput? _fitImageToLimit(_ImageFitInput input) {
  try {
    return _fitImageToLimitUnchecked(input);
  } catch (_) {
    return null;
  }
}

_ImageFitOutput? _fitImageToLimitUnchecked(_ImageFitInput input) {
  final decoded = image_lib.decodeImage(input.bytes);
  if (decoded == null) return null;

  var outputName = input.name;
  var outputMime = input.mimeType;
  if (outputMime == 'image/webp') {
    outputMime = 'image/png';
    outputName = outputName.replaceFirst(
      RegExp(r'\.webp$', caseSensitive: false),
      '.png',
    );
  }

  var scale = 0.9;
  while (scale > 0.01) {
    final width = (decoded.width * scale).round().clamp(1, decoded.width);
    final height = (decoded.height * scale).round().clamp(1, decoded.height);
    final resized = image_lib.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: image_lib.Interpolation.average,
    );
    final encoded = switch (outputMime) {
      'image/jpeg' => image_lib.encodeJpg(resized, quality: 85),
      'image/gif' => image_lib.encodeGif(resized),
      'image/bmp' => image_lib.encodeBmp(resized),
      _ => image_lib.encodePng(resized, level: 9),
    };
    if (encoded.length <= input.limitBytes) {
      return (name: outputName, mimeType: outputMime, bytes: encoded);
    }
    scale *= 0.82;
  }
  return null;
}

/// Handles file picking, validation, and MIME type inference.
class FilePickerHelper {
  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

  /// Whether the running platform is a phone/tablet where the device camera
  /// and native photo picker make sense. On the web, [defaultTargetPlatform]
  /// reflects the underlying OS, so mobile browsers count too.
  static bool get isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Capture a photo with the device camera. Mobile platforms only
  /// (see [isMobilePlatform]).
  static Future<FilePickResult?> takePhoto({
    required Set<String> existingNames,
  }) async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null) return null;

    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final name =
        'photo_${now.year}${pad(now.month)}${pad(now.day)}'
        '_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}.jpg';

    return await validate(
      files: [(name: name, bytes: await photo.readAsBytes())],
      existingNames: existingNames,
    );
  }

  /// Pick images only: the native photo picker on mobile, the file picker
  /// restricted to image extensions everywhere else.
  static Future<FilePickResult?> pickImages({
    required Set<String> existingNames,
  }) async {
    if (isMobilePlatform) {
      final photos = await ImagePicker().pickMultiImage();
      if (photos.isEmpty) return null;
      return await validate(
        files: [
          for (final photo in photos)
            (name: photo.name, bytes: await photo.readAsBytes()),
        ],
        existingNames: existingNames,
      );
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _imageExtensions,
    );
    if (result == null) return null;

    return await validate(
      files: [
        for (final file in result.files)
          if (file.bytes != null) (name: file.name, bytes: file.bytes!),
      ],
      existingNames: existingNames,
    );
  }

  /// Open the file picker and validate selected files.
  /// [existingNames] is used to detect duplicate filenames.
  static Future<FilePickResult?> pickFiles({
    required Set<String> existingNames,
  }) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        // images
        ..._imageExtensions,
        // documents
        'txt', 'md', 'csv', 'json', 'xml', 'yaml', 'yml',
        'html', 'htm', 'css', 'js', 'ts', 'py', 'dart', 'rs',
        'go', 'java', 'kt', 'swift', 'c', 'cpp', 'h',
        'pdf', 'xlsx', 'xls', 'ods',
      ],
    );

    if (result == null) return null;

    return await validate(
      files: [
        for (final file in result.files)
          if (file.bytes != null) (name: file.name, bytes: file.bytes!),
      ],
      existingNames: existingNames,
    );
  }

  /// Validate raw files against size limits and duplicate names.
  ///
  /// Single source of truth for attachment validation — shared by the file
  /// picker above and the chat page's drag-and-drop path.
  static Future<FilePickResult> validate({
    required Iterable<RawPickedFile> files,
    required Set<String> existingNames,
    @visibleForTesting int imageLimitBytes = _maxImageBytes,
  }) async {
    final added = <ChatAttachment>[];
    final rejected = <String>[];
    final validationErrors = <String>[];
    final seenNames = {...existingNames};

    for (final file in files) {
      var bytes = file.bytes;
      var name = file.name;
      var mime = inferMime(name, bytes);
      final isImage = mime.startsWith('image/');
      final isPdf = mime == 'application/pdf';
      final isSpreadsheet =
          mime.endsWith('spreadsheetml.sheet') ||
          mime == 'application/vnd.ms-excel' ||
          mime == 'application/vnd.oasis.opendocument.spreadsheet' ||
          name.toLowerCase().endsWith('.csv') ||
          name.toLowerCase().endsWith('.xlsx') ||
          name.toLowerCase().endsWith('.xls') ||
          name.toLowerCase().endsWith('.ods');

      if (isImage && bytes.length > imageLimitBytes) {
        final fitted = await compute(_fitImageToLimit, (
          name: name,
          mimeType: mime,
          bytes: bytes,
          limitBytes: imageLimitBytes,
        ));
        if (fitted == null) {
          rejected.add(
            '$name (${formatBytes(bytes.length)} - could not resize)',
          );
          continue;
        }
        name = fitted.name;
        mime = fitted.mimeType;
        bytes = fitted.bytes;
      }

      final maxBytes = isPdf
          ? 20 * 1024 * 1024
          : isSpreadsheet
          ? 10 * 1024 * 1024
          : 10 * 1024 * 1024;

      if (!isImage && bytes.length > maxBytes) {
        rejected.add(
          '$name (${formatBytes(bytes.length)} - max ${formatBytes(maxBytes)})',
        );
        continue;
      }

      if (seenNames.contains(name)) {
        validationErrors.add('Duplicate file: $name');
        continue;
      }

      added.add(
        ChatAttachment.fromPicked(name: name, mimeType: mime, bytes: bytes),
      );
      seenNames.add(name);
    }

    return FilePickResult(
      added: added,
      rejected: rejected,
      validationErrors: validationErrors,
    );
  }

  static String inferMime(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xml')) return 'application/xml';
    return 'text/plain';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
