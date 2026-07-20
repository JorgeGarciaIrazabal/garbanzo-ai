import 'package:garbanzo_ai/features/chat/services/folder_read_error.dart';
import 'package:garbanzo_ai/features/chat/services/folder_walk.dart';

/// Web stub: folders can't be attached or read without a filesystem, so every
/// operation reports it's unsupported. (In practice the client never sets
/// `has_client_folder` on web, so the backend never asks it to serve a read.)
class FolderReader {
  const FolderReader();

  static const int maxFileBytes = 5 * 1024 * 1024;

  String? safeResolve(String root, String relPath) => null;

  ({String filename, List<int> bytes}) readFile(String root, String relPath) {
    throw const FolderReadError('Folder reads are not supported on web.');
  }

  List<Map<String, Object>> listDir(String root, String relPath) {
    throw const FolderReadError('Folder reads are not supported on web.');
  }

  FolderWalk walk(
    String root, {
    int maxFiles = 2000,
    int maxTotalBytes = 50 * 1024 * 1024,
  }) {
    throw const FolderReadError('Folder reads are not supported on web.');
  }
}
