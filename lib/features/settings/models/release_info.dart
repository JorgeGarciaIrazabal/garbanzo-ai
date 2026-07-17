/// A downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
    name: json['name'] as String? ?? '',
    downloadUrl: json['download_url'] as String? ?? '',
    size: json['size'] as int? ?? 0,
  );

  /// GitHub's own asset shape (used by the direct-to-GitHub fallback).
  factory ReleaseAsset.fromGitHubJson(Map<String, dynamic> json) =>
      ReleaseAsset(
        name: json['name'] as String? ?? '',
        downloadUrl: json['browser_download_url'] as String? ?? '',
        size: json['size'] as int? ?? 0,
      );
}

/// The latest published release, as served by `GET /api/v1/version/latest`
/// (or the GitHub API directly when the backend predates that endpoint).
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.assets,
    this.name,
    this.body,
    this.publishedAt,
  });

  /// Tag with any leading `v` stripped, e.g. `1.0.4`.
  final String version;
  final String tagName;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final String? name;

  /// Release notes (markdown).
  final String? body;
  final DateTime? publishedAt;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) => ReleaseInfo(
    version: json['version'] as String? ?? '',
    tagName: json['tag_name'] as String? ?? '',
    htmlUrl: json['html_url'] as String? ?? '',
    name: json['name'] as String?,
    body: json['body'] as String?,
    publishedAt: json['published_at'] != null
        ? DateTime.tryParse(json['published_at'] as String)
        : null,
    assets: (json['assets'] as List? ?? const [])
        .map((a) => ReleaseAsset.fromJson(a as Map<String, dynamic>))
        .toList(),
  );

  factory ReleaseInfo.fromGitHubJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      tagName: tag,
      htmlUrl: json['html_url'] as String? ?? '',
      name: json['name'] as String?,
      body: json['body'] as String?,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String)
          : null,
      assets: (json['assets'] as List? ?? const [])
          .map((a) => ReleaseAsset.fromGitHubJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Outcome of an update check: what we run vs what's published.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.release,
    required this.hasUpdate,
    this.asset,
  });

  final String currentVersion;
  final ReleaseInfo release;
  final bool hasUpdate;

  /// The release asset matching the running platform (null if none published).
  final ReleaseAsset? asset;
}
