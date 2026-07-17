import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/platform_info.dart';
import 'package:garbanzo_ai/features/settings/models/release_info.dart';

/// GitHub repo used when the backend doesn't expose `/api/v1/version/latest`
/// yet (a backend older than the updater itself).
const _fallbackGitHubRepo = 'JorgeGarciaIrazabal/garbanzo-ai';

/// Compares two dotted version strings numerically (`1.0.10` > `1.0.9`).
///
/// Build metadata / prerelease suffixes (`+1`, `-dev`) are ignored; missing
/// components count as 0. Returns <0, 0, or >0 like a comparator.
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final pa = parse(a), pb = parse(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final ca = i < pa.length ? pa[i] : 0;
    final cb = i < pb.length ? pb[i] : 0;
    if (ca != cb) return ca.compareTo(cb);
  }
  return 0;
}

/// Picks the release asset for the running desktop platform:
/// Linux → `*linux*.tar.gz`, Windows → `*windows*.zip`.
ReleaseAsset? assetForPlatform(
  List<ReleaseAsset> assets, {
  bool? isLinux,
  bool? isWindows,
}) {
  final linux = isLinux ?? PlatformInfo.isLinux;
  final windows = isWindows ?? PlatformInfo.isWindows;
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (linux && name.contains('linux') && name.endsWith('.tar.gz')) {
      return asset;
    }
    if (windows && name.contains('windows') && name.endsWith('.zip')) {
      return asset;
    }
  }
  return null;
}

/// Checks GitHub Releases (via the backend proxy) for a newer desktop build.
class UpdateService {
  UpdateService({
    Future<Response> Function(String path)? apiGet,
    Future<String> Function()? currentVersion,
  }) : _apiGet = apiGet,
       _currentVersion = currentVersion;

  static final UpdateService instance = UpdateService();

  final Future<Response> Function(String path)? _apiGet;
  final Future<String> Function()? _currentVersion;

  Future<String> _runningVersion() async {
    if (_currentVersion != null) return _currentVersion();
    return (await PackageInfo.fromPlatform()).version;
  }

  /// Latest release from the backend proxy, falling back to the GitHub API
  /// directly when the backend predates `GET /api/v1/version/latest`.
  Future<ReleaseInfo> fetchLatestRelease() async {
    final get = _apiGet ?? ApiClient.instance.get;
    final response = await get('/api/v1/version/latest');
    if (response.statusCode == 200) {
      return ReleaseInfo.fromJson(response.data as Map<String, dynamic>);
    }
    if (response.statusCode == 404) {
      return _fetchFromGitHub();
    }
    throw Exception('Update check failed (HTTP ${response.statusCode})');
  }

  Future<ReleaseInfo> _fetchFromGitHub() async {
    final response = await Dio().get(
      'https://api.github.com/repos/$_fallbackGitHubRepo/releases/latest',
      options: Options(
        headers: {'Accept': 'application/vnd.github+json'},
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub returned HTTP ${response.statusCode}');
    }
    return ReleaseInfo.fromGitHubJson(response.data as Map<String, dynamic>);
  }

  /// Compares the running app version against the latest release.
  Future<UpdateCheckResult> checkForUpdates() async {
    final current = await _runningVersion();
    final release = await fetchLatestRelease();
    final hasUpdate =
        release.version.isNotEmpty &&
        compareVersions(release.version, current) > 0;
    return UpdateCheckResult(
      currentVersion: current,
      release: release,
      hasUpdate: hasUpdate,
      asset: assetForPlatform(release.assets),
    );
  }
}
