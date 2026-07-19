/// Raised by [FolderReader] when a requested path escapes the attached folder,
/// is missing, too large, or unreadable on this platform.
class FolderReadError implements Exception {
  const FolderReadError(this.message);
  final String message;
  @override
  String toString() => message;
}
