import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/core/platform_info.dart';
import 'package:garbanzo_ai/features/settings/models/release_info.dart';
import 'package:garbanzo_ai/features/settings/services/update_installer.dart';
import 'package:garbanzo_ai/features/settings/services/update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error,
}

/// Desktop auto-update state: silent check on startup, manual "Check now",
/// download/install progress, and banner snoozing ("Later" hides the banner
/// for [snoozeDuration] per version; the Settings section always shows the
/// real state).
///
/// On non-desktop platforms every entry point is a no-op and [showBanner]
/// stays false — the whole feature is desktop-only.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider({UpdateService? service, UpdateInstaller? installer})
    : _service = service ?? UpdateService.instance,
      _installer = installer ?? UpdateInstaller();

  static const _keySnoozedVersion = 'update_snoozed_version';
  static const _keySnoozeUntilMs = 'update_snooze_until_ms';
  static const snoozeDuration = Duration(days: 3);

  final UpdateService _service;
  final UpdateInstaller _installer;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateCheckResult? _result;
  double? _downloadProgress;
  String? _errorMessage;
  String? _snoozedVersion;
  DateTime? _snoozeUntil;
  bool _bannerDismissed = false;

  UpdateStatus get status => _status;
  UpdateCheckResult? get result => _result;
  double? get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  bool get busy =>
      _status == UpdateStatus.downloading || _status == UpdateStatus.installing;

  /// Whether the "vX is available" banner should be visible.
  bool get showBanner {
    final r = _result;
    if (r == null || !r.hasUpdate || _bannerDismissed) return false;
    if (_status != UpdateStatus.available) return false;
    if (_snoozedVersion == r.release.version &&
        _snoozeUntil != null &&
        DateTime.now().isBefore(_snoozeUntil!)) {
      return false;
    }
    return true;
  }

  /// Startup check: quiet on any failure, skipped off-desktop.
  Future<void> silentCheck() async {
    if (!PlatformInfo.isDesktop) return;
    try {
      await _check();
    } catch (e) {
      logDebug('update: silent check failed: $e');
      _status = UpdateStatus.idle;
      notifyListeners();
    }
  }

  /// Manual check from Settings — surfaces errors.
  Future<void> checkNow() async {
    if (!PlatformInfo.isDesktop || busy) return;
    try {
      await _check();
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> _check() async {
    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();
    await _loadSnooze();
    final result = await _service.checkForUpdates();
    _result = result;
    _status = result.hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate;
    notifyListeners();
  }

  /// "Later" on the banner: hide it for this version for [snoozeDuration].
  Future<void> snooze() async {
    final r = _result;
    if (r == null) return;
    _snoozedVersion = r.release.version;
    _snoozeUntil = DateTime.now().add(snoozeDuration);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySnoozedVersion, _snoozedVersion!);
    await prefs.setInt(_keySnoozeUntilMs, _snoozeUntil!.millisecondsSinceEpoch);
  }

  /// Hide the banner for the rest of this session (e.g. after opening the
  /// update dialog from it) without persisting anything.
  void dismissBanner() {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
  }

  /// Download + install + relaunch. On success the process exits.
  Future<void> downloadAndInstall() async {
    final asset = _result?.asset;
    if (asset == null || busy) return;
    _status = UpdateStatus.downloading;
    _downloadProgress = 0;
    _errorMessage = null;
    notifyListeners();
    try {
      await _installer.installAndRestart(
        asset,
        onProgress: (p) {
          _downloadProgress = p;
          if (p == 1.0) _status = UpdateStatus.installing;
          notifyListeners();
        },
      );
    } catch (e) {
      _status = UpdateStatus.error;
      _downloadProgress = null;
      _errorMessage =
          'Update failed: $e\nYou can download it manually from the '
          'releases page.';
      notifyListeners();
    }
  }

  Future<void> _loadSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    _snoozedVersion = prefs.getString(_keySnoozedVersion);
    final untilMs = prefs.getInt(_keySnoozeUntilMs);
    _snoozeUntil = untilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(untilMs)
        : null;
  }
}
