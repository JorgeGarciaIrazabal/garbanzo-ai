import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:garbanzo_ai/features/chat/services/folder_read_error.dart';
import 'package:garbanzo_ai/features/chat/services/folder_walk.dart';

/// Client-side reader for a folder the user attached to a conversation
/// (idea 17). The folder lives only on this desktop client; when the backend
/// asks (`client_tool_request`), we read the requested path here and send the
/// result back — the backend never touches the host filesystem.
///
/// Every requested path is forced back inside the attached [root] by
/// [safeResolve], so the model can never make us read outside the folder.
class FolderReader {
  const FolderReader();

  /// Largest file we'll read and upload; mirrors the backend's cap.
  static const int maxFileBytes = 5 * 1024 * 1024;

  static const int _maxListEntries = 500;
  static const Set<String> _skipNames = {
    '.git',
    '.hg',
    '.svn',
    '__pycache__',
    'node_modules',
  };

  /// Resolve [relPath] inside [root], returning the absolute path, or null if
  /// it escapes the folder. Catches `../` traversal, absolute paths, and
  /// symlinks that point outside the root.
  String? safeResolve(String root, String relPath) {
    final rootAbs = p.canonicalize(root);
    final candidate = p.canonicalize(p.join(rootAbs, relPath));
    if (candidate != rootAbs && !p.isWithin(rootAbs, candidate)) return null;

    // If the target exists, resolve symlinks and re-check containment.
    if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
      try {
        final real = p.canonicalize(File(candidate).resolveSymbolicLinksSync());
        if (real != rootAbs && !p.isWithin(rootAbs, real)) return null;
        return real;
      } catch (_) {
        // Fall through to the lexically-checked candidate.
      }
    }
    return candidate;
  }

  /// Read a file inside [root]. Returns its name + bytes, or throws
  /// [FolderReadError] on escape / missing / oversized.
  ({String filename, List<int> bytes}) readFile(String root, String relPath) {
    final resolved = safeResolve(root, relPath);
    if (resolved == null) {
      throw const FolderReadError('Path escapes the attached folder.');
    }
    final file = File(resolved);
    if (!file.existsSync()) {
      throw FolderReadError('File not found: $relPath');
    }
    final length = file.lengthSync();
    if (length > maxFileBytes) {
      throw FolderReadError(
        'File is too large (${length ~/ 1024} KB > ${maxFileBytes ~/ 1024} KB).',
      );
    }
    return (filename: p.basename(resolved), bytes: file.readAsBytesSync());
  }

  /// Recursively collect every readable file under [root], as paths relative
  /// to it. Used to snapshot the folder for a delegated workflow (idea 18).
  ///
  /// Applies the same skip rules as [listDir] plus the size caps, so build
  /// output and giant binaries never get uploaded. Stops at [maxFiles] /
  /// [maxTotalBytes] and reports what it skipped rather than failing — a
  /// partial snapshot with a warning beats refusing to run.
  FolderWalk walk(
    String root, {
    int maxFiles = 2000,
    int maxTotalBytes = 50 * 1024 * 1024,
  }) {
    final rootAbs = p.canonicalize(root);
    final paths = <String>[];
    final skipped = <String>[];
    var totalBytes = 0;
    var truncated = false;

    void visit(Directory dir) {
      if (truncated) return;
      final List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } on FileSystemException {
        return; // unreadable directory — skip it, don't abort the walk
      }
      children.sort((a, b) => a.path.compareTo(b.path));
      for (final entity in children) {
        if (truncated) return;
        final name = p.basename(entity.path);
        if (name.startsWith('.') || _skipNames.contains(name)) continue;
        if (entity is Directory) {
          visit(entity);
          continue;
        }
        if (entity is! File) continue; // symlinks and sockets
        final rel = p.relative(entity.path, from: rootAbs);
        final int length;
        try {
          length = entity.lengthSync();
        } on FileSystemException {
          skipped.add(rel);
          continue;
        }
        if (length > maxFileBytes) {
          skipped.add(rel);
          continue;
        }
        if (paths.length >= maxFiles || totalBytes + length > maxTotalBytes) {
          truncated = true;
          return;
        }
        paths.add(rel);
        totalBytes += length;
      }
    }

    visit(Directory(rootAbs));
    return FolderWalk(
      paths: paths,
      totalBytes: totalBytes,
      skipped: skipped,
      truncated: truncated,
    );
  }

  /// List entries directly under [relPath] inside [root]. Skips dotfiles and
  /// VCS/build noise; capped so a huge directory can't overflow the result.
  List<Map<String, Object>> listDir(String root, String relPath) {
    final resolved = safeResolve(root, relPath.isEmpty ? '.' : relPath);
    if (resolved == null) {
      throw const FolderReadError('Path escapes the attached folder.');
    }
    final dir = Directory(resolved);
    if (!dir.existsSync()) {
      throw FolderReadError('Not a directory: $relPath');
    }
    final rootAbs = p.canonicalize(root);
    final entries = <Map<String, Object>>[];
    final children = dir.listSync()
      ..sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
    for (final entity in children) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') || _skipNames.contains(name)) continue;
      final isDir = entity is Directory;
      entries.add({
        'path': p.relative(entity.path, from: rootAbs),
        'is_dir': isDir,
        'size': isDir ? 0 : File(entity.path).lengthSync(),
      });
      if (entries.length >= _maxListEntries) break;
    }
    return entries;
  }
}
