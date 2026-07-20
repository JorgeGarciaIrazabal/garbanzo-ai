/// Result of recursively scanning an attached folder before uploading it as a
/// delegated workflow's snapshot (idea 18).
///
/// Platform-independent so both the `dart:io` reader and the web stub can
/// return one.
class FolderWalk {
  const FolderWalk({
    required this.paths,
    required this.totalBytes,
    this.skipped = const [],
    this.truncated = false,
  });

  /// File paths relative to the folder root, in a stable order.
  final List<String> paths;

  /// Combined size of [paths].
  final int totalBytes;

  /// Files left out because they were too large or unreadable.
  final List<String> skipped;

  /// True when the walk hit the file-count or total-size cap and stopped
  /// early — the snapshot is incomplete and the user should be told.
  final bool truncated;

  bool get isEmpty => paths.isEmpty;
}
