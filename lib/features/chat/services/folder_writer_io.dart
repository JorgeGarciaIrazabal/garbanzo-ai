import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:garbanzo_ai/features/chat/services/folder_read_error.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader_io.dart';

/// Writes a delegated workflow's changes back into the attached folder
/// (idea 18), on the client — the backend never touches the user's disk.
///
/// Every write goes through [FolderReader.safeResolve], so a change whose path
/// escapes the folder is refused no matter what the server returned. Callers
/// are expected to check [hashFile] against the change's `base_sha256` first:
/// this class writes what it is told, the conflict policy lives above it.
class FolderWriter {
  const FolderWriter({FolderReader reader = const FolderReader()})
    : _reader = reader;

  final FolderReader _reader;

  String _resolve(String root, String relPath) {
    final resolved = _reader.safeResolve(root, relPath);
    if (resolved == null) {
      throw FolderReadError('Path escapes the attached folder: $relPath');
    }
    return resolved;
  }

  /// sha256 of the file's current bytes, or null when it doesn't exist.
  /// Used to detect a file the user edited while the workflow was running.
  String? hashFile(String root, String relPath) {
    final resolved = _reader.safeResolve(root, relPath);
    if (resolved == null) return null;
    final file = File(resolved);
    if (!file.existsSync()) return null;
    return sha256.convert(file.readAsBytesSync()).toString();
  }

  /// Create or overwrite a file, making parent directories as needed.
  void writeFile(String root, String relPath, List<int> bytes) {
    final resolved = _resolve(root, relPath);
    Directory(p.dirname(resolved)).createSync(recursive: true);
    File(resolved).writeAsBytesSync(bytes);
  }

  /// Delete a file. A file that's already gone is not an error — the end
  /// state the workflow asked for is what matters.
  void deleteFile(String root, String relPath) {
    final resolved = _resolve(root, relPath);
    final file = File(resolved);
    if (file.existsSync()) file.deleteSync();
  }
}
