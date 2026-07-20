import 'package:garbanzo_ai/features/chat/services/folder_read_error.dart';

/// Web stub: there is no filesystem to write back to, and web can never
/// attach a folder in the first place, so every operation reports as
/// unsupported.
class FolderWriter {
  const FolderWriter();

  String? hashFile(String root, String relPath) => null;

  void writeFile(String root, String relPath, List<int> bytes) {
    throw const FolderReadError('Folder writes are not supported on web.');
  }

  void deleteFile(String root, String relPath) {
    throw const FolderReadError('Folder writes are not supported on web.');
  }
}
