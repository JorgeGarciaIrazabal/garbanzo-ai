import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:garbanzo_ai/core/log.dart';

/// An image read out of the system clipboard, ready for the same validation
/// every other attachment entry path goes through.
typedef ClipboardImage = ({String name, Uint8List bytes});

/// Reads image data from the system clipboard (Ctrl/Cmd+V).
///
/// A screenshot or a "Copy image" from a browser normally lands on the
/// clipboard as raw pixels, with no file and no text — the composer's plain
/// text paste has nothing to work with, so images need this dedicated read.
///
/// Returns an empty list when the clipboard holds no image (the caller then
/// falls back to pasting text). Clipboard access is a genuinely optional
/// platform capability — web without the async clipboard API, or a headless
/// test binding — so an unavailable reader yields "no image" rather than an
/// error the composer cannot act on.
class ClipboardImageReader {
  ClipboardImageReader._();

  /// Test seam: replaces the platform read so widget tests can drive paste
  /// without a real clipboard. Set to null to restore the real reader.
  @visibleForTesting
  static Future<List<ClipboardImage>> Function()? debugOverride;

  /// Total budget for probing the clipboard. Short enough that a stalled or
  /// permission-prompting clipboard never delays an ordinary paste.
  static const Duration _readBudget = Duration(seconds: 5);

  /// Formats to probe, in order, paired with the extension used to name the
  /// attachment (the name drives MIME inference in validation).
  ///
  /// PNG comes first because `super_clipboard` exposes Windows DIB/DIBv5 and
  /// macOS TIFF clipboard images as PNG on demand — on those platforms the
  /// PNG probe is what actually sees a copied screenshot. The rest cover
  /// platforms that hand over an already-encoded file.
  static const List<(FileFormat, String)> _candidates = [
    (Formats.png, '.png'),
    (Formats.jpeg, '.jpeg'),
    (Formats.gif, '.gif'),
    (Formats.webp, '.webp'),
    (Formats.bmp, '.bmp'),
  ];

  /// Reads the clipboard's first image, or an empty list when there is none.
  ///
  /// Never throws, and never blocks for long: this runs on every Ctrl/Cmd+V
  /// before the plain-text paste, so a slow or permission-prompting clipboard
  /// must not make ordinary typing feel stalled. The capability is genuinely
  /// optional (web without the async clipboard API), so an unavailable or
  /// failed read yields "no image" and the text paste proceeds.
  static Future<List<ClipboardImage>> readImages() async {
    final override = debugOverride;
    if (override != null) return override();
    try {
      return await _readFromSystemClipboard().timeout(_readBudget);
    } on TimeoutException {
      logDebug('Clipboard image probe timed out; pasting text instead');
      return const [];
    } on MissingPluginException catch (error) {
      logDebug('Clipboard image read unavailable: $error');
      return const [];
    } on UnsupportedError catch (error) {
      logDebug('Clipboard image read unsupported on this platform: $error');
      return const [];
    } catch (error) {
      logDebug('Clipboard image read failed: $error');
      return const [];
    }
  }

  static Future<List<ClipboardImage>> _readFromSystemClipboard() async {
    final clipboard = SystemClipboard.instance;
    // Null when the platform has no async clipboard API (Firefox).
    if (clipboard == null) return const [];

    final reader = await clipboard.read();
    for (final (format, extension) in _candidates) {
      if (!reader.canProvide(format)) continue;
      final bytes = await _readFile(reader, format, extension);
      if (bytes == null || bytes.isEmpty) continue;
      return [(name: _pastedImageName(extension), bytes: bytes)];
    }
    return const [];
  }

  /// Loads one clipboard format as bytes, or null when the platform reports
  /// the format as available but cannot actually hand over the data.
  static Future<Uint8List?> _readFile(
    ClipboardReader reader,
    FileFormat format,
    String extension,
  ) async {
    final completer = Completer<Uint8List?>();
    // getFile's callback is the only place the file may be streamed from, so
    // the read has to happen inside it — hence the completer.
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          completer.complete(await file.readAll());
        } catch (error, stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        }
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    // Null progress means the value can never arrive (canProvide was
    // optimistic); without this guard the await below would hang.
    if (progress == null) return null;
    // A stuck platform read must not wedge the composer, and an image is
    // never essential to pasting.
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        logDebug('Clipboard image read timed out for $extension');
        return null;
      },
    );
  }

  static String _pastedImageName(String extension) {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return 'pasted_${now.year}${pad(now.month)}${pad(now.day)}'
        '_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}$extension';
  }
}
