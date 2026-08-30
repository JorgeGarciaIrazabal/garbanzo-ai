import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/settings/models/release_info.dart';

class UpdateInstallPermissionRequired implements Exception {
  const UpdateInstallPermissionRequired();
}

/// Downloads a release asset and installs it using the platform-native flow.
///
/// Linux: extract the `.tar.gz` to a staging dir **next to** the install dir
/// (same filesystem, so `rename` is atomic and legal while the app runs —
/// open file handles keep their inodes alive), swap directories, relaunch the
/// new binary, and exit. The previous install stays at `<install>.old` as a
/// manual rollback until the next update overwrites it.
///
/// Windows: a running exe's files are locked, so extract to staging, write a
/// batch script that waits for this process to exit, copies staging over the
/// install dir, and relaunches — then exit to let it run.
///
/// Android: ask for the per-source package-install authorization before the
/// download, then stream the APK into Android's PackageInstaller. Android owns
/// the final confirmation UI and restarts the updated app.
class UpdateInstaller {
  UpdateInstaller({
    Dio? dio,
    bool? isAndroid,
    Future<bool> Function()? ensureAndroidInstallPermission,
    Future<void> Function(String apkPath)? installAndroidPackage,
  }) : _dio = dio ?? Dio(),
       _isAndroidOverride = isAndroid,
       _ensureAndroidInstallPermission = ensureAndroidInstallPermission,
       _installAndroidPackage = installAndroidPackage;

  static const _androidChannel = MethodChannel(
    'com.example.garbanzo_ai/app_update',
  );

  final Dio _dio;
  final bool? _isAndroidOverride;
  final Future<bool> Function()? _ensureAndroidInstallPermission;
  final Future<void> Function(String apkPath)? _installAndroidPackage;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  /// Opens Android's per-source authorization page when permission is absent.
  /// This runs before downloading so a first-time permission grant never wastes
  /// an 80+ MB APK download.
  Future<void> prepareInstall() async {
    if (!_isAndroid) return;
    final ensurePermission =
        _ensureAndroidInstallPermission ??
        () async =>
            await _androidChannel.invokeMethod<bool>(
              'ensureInstallPermission',
            ) ??
            false;
    if (!await ensurePermission()) {
      throw const UpdateInstallPermissionRequired();
    }
  }

  /// Downloads [asset], installs it, and restarts where the platform supports
  /// that. Desktop success exits the process; Android waits for the package
  /// installer result (a successful update replaces this process).
  ///
  /// [onProgress] receives 0..1 while downloading (null = indeterminate).
  Future<void> installAndRestart(
    ReleaseAsset asset, {
    void Function(double? progress)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('garbanzo-update-');
    try {
      final archive = File('${tempDir.path}/${asset.name}');
      await _download(asset, archive, onProgress);
      onProgress?.call(1.0);

      if (_isAndroid) {
        final installPackage =
            _installAndroidPackage ??
            (path) => _androidChannel.invokeMethod<void>('installApk', path);
        await installPackage(archive.path);
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        return;
      }

      final exe = File(Platform.resolvedExecutable);
      final installDir = exe.parent;

      final staging = Directory('${installDir.path}.staging');
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);
      await _extract(archive, staging);
      _verifyStaging(staging, exeName: exe.uri.pathSegments.last);

      if (Platform.isLinux) {
        swapDirs(install: installDir, staging: staging);
        await Process.start(
          exe.path,
          const [],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isWindows) {
        await _spawnWindowsSwapScript(
          staging: staging,
          installDir: installDir,
          exePath: exe.path,
        );
      } else {
        throw UnsupportedError(
          'Self-upgrade is Linux, Windows, or Android only',
        );
      }
    } catch (e) {
      // Only reached on failure — clean the downloaded archive and rethrow.
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
      rethrow;
    }
    exit(0);
  }

  Future<void> _download(
    ReleaseAsset asset,
    File target,
    void Function(double?)? onProgress,
  ) async {
    final response = await _dio.download(
      asset.downloadUrl,
      target.path,
      onReceiveProgress: (received, total) {
        onProgress?.call(total > 0 ? received / total : null);
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Download failed (HTTP ${response.statusCode})');
    }
    if (!target.existsSync() || target.lengthSync() == 0) {
      throw Exception('Downloaded archive is empty');
    }
  }

  /// Extracts with the platform's native tool — preserves the executable bit
  /// on Linux (which pure-Dart unarchivers don't) and avoids a new dependency.
  Future<void> _extract(File archive, Directory staging) async {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Path "${archive.path}" '
            '-DestinationPath "${staging.path}" -Force',
      ]);
    } else {
      result = await Process.run('tar', [
        'xzf',
        archive.path,
        '-C',
        staging.path,
      ]);
    }
    if (result.exitCode != 0) {
      throw Exception('Extraction failed: ${result.stderr}');
    }
  }

  void _verifyStaging(Directory staging, {required String exeName}) {
    final exe = File('${staging.path}/$exeName');
    if (!exe.existsSync()) {
      throw Exception(
        'Update archive does not contain "$exeName" — refusing to install',
      );
    }
  }

  /// Atomic-rename swap: install → `.old` (rollback copy), staging → install.
  /// Visible for tests. If the second rename fails, roll the old dir back so
  /// the app is never left without an install directory.
  static void swapDirs({
    required Directory install,
    required Directory staging,
  }) {
    final old = Directory('${install.path}.old');
    if (old.existsSync()) old.deleteSync(recursive: true);
    install.renameSync(old.path);
    try {
      staging.renameSync(install.path);
    } catch (_) {
      old.renameSync(install.path);
      rethrow;
    }
  }

  Future<void> _spawnWindowsSwapScript({
    required Directory staging,
    required Directory installDir,
    required String exePath,
  }) async {
    final script = File('${staging.path}\\..\\garbanzo-update.bat');
    // robocopy exit codes < 8 mean success; /MIR removes files dropped from
    // the release. The script deletes staging and itself when done.
    script.writeAsStringSync('''
@echo off
timeout /t 2 /nobreak >nul
robocopy "${staging.path}" "${installDir.path}" /MIR >nul
if %ERRORLEVEL% GEQ 8 exit /b 1
rmdir /s /q "${staging.path}"
start "" "$exePath"
del "%~f0"
''');
    await Process.start('cmd', [
      '/c',
      script.path,
    ], mode: ProcessStartMode.detached);
    logDebug('update: Windows swap script started — exiting to let it run');
  }
}
