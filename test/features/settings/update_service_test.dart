import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/settings/models/release_info.dart';
import 'package:garbanzo_ai/features/settings/providers/update_provider.dart';
import 'package:garbanzo_ai/features/settings/services/update_installer.dart';
import 'package:garbanzo_ai/features/settings/services/update_service.dart';

Response<dynamic> _response(int status, [Object? data]) => Response(
  requestOptions: RequestOptions(path: '/api/v1/version/latest'),
  statusCode: status,
  data: data,
);

Map<String, dynamic> _releaseJson(String version) => {
  'version': version,
  'tag_name': 'v$version',
  'name': 'Release v$version',
  'body': '- fixes',
  'published_at': '2026-07-01T12:00:00Z',
  'html_url': 'https://github.com/o/r/releases/tag/v$version',
  'assets': [
    {
      'name': 'garbanzo-ai-linux-$version.tar.gz',
      'download_url': 'https://example.com/linux.tar.gz',
      'size': 10,
    },
    {
      'name': 'garbanzo-ai-windows-$version.zip',
      'download_url': 'https://example.com/windows.zip',
      'size': 20,
    },
  ],
};

UpdateService _service(String current, String latest) => UpdateService(
  apiGet: (_) async => _response(200, _releaseJson(latest)),
  currentVersion: () async => current,
);

void main() {
  group('compareVersions', () {
    test('orders numerically, not lexically', () {
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
    });

    test('equal versions compare 0, ignoring build/prerelease suffixes', () {
      expect(compareVersions('1.0.3', '1.0.3'), 0);
      expect(compareVersions('1.0.3+7', '1.0.3'), 0);
      expect(compareVersions('1.0.3-dev', '1.0.3'), 0);
    });

    test('missing components count as zero', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.1', '1.0.5'), greaterThan(0));
    });
  });

  group('assetForPlatform', () {
    final assets = ReleaseInfo.fromJson(_releaseJson('1.0.4')).assets;

    test('picks the linux tar.gz on Linux', () {
      final asset = assetForPlatform(assets, isLinux: true, isWindows: false);
      expect(asset?.name, 'garbanzo-ai-linux-1.0.4.tar.gz');
    });

    test('picks the windows zip on Windows', () {
      final asset = assetForPlatform(assets, isLinux: false, isWindows: true);
      expect(asset?.name, 'garbanzo-ai-windows-1.0.4.zip');
    });

    test('returns null when nothing matches', () {
      expect(
        assetForPlatform(const [], isLinux: true, isWindows: false),
        isNull,
      );
    });
  });

  group('UpdateService.checkForUpdates', () {
    test('reports an update when the release is newer', () async {
      final result = await _service('1.0.3', '1.0.4').checkForUpdates();
      expect(result.hasUpdate, isTrue);
      expect(result.currentVersion, '1.0.3');
      expect(result.release.version, '1.0.4');
    });

    test('reports up-to-date when running the latest (or newer)', () async {
      expect((await _service('1.0.4', '1.0.4').checkForUpdates()).hasUpdate,
          isFalse);
      expect((await _service('1.0.5', '1.0.4').checkForUpdates()).hasUpdate,
          isFalse);
    });

    test('throws on backend errors other than 404', () async {
      final service = UpdateService(
        apiGet: (_) async => _response(500),
        currentVersion: () async => '1.0.3',
      );
      expect(service.checkForUpdates(), throwsException);
    });
  });

  group('UpdateProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    UpdateProvider provider(String current, String latest) => UpdateProvider(
      service: _service(current, latest),
      installer: UpdateInstaller(),
    );

    test('silent check exposes an available update and shows the banner',
        () async {
      final p = provider('1.0.3', '1.0.4');
      await p.silentCheck();
      expect(p.status, UpdateStatus.available);
      expect(p.showBanner, isTrue);
    });

    test('up-to-date check shows no banner', () async {
      final p = provider('1.0.4', '1.0.4');
      await p.silentCheck();
      expect(p.status, UpdateStatus.upToDate);
      expect(p.showBanner, isFalse);
    });

    test('snooze hides the banner and persists across provider instances',
        () async {
      final p = provider('1.0.3', '1.0.4');
      await p.silentCheck();
      await p.snooze();
      expect(p.showBanner, isFalse);

      final fresh = provider('1.0.3', '1.0.4');
      await fresh.silentCheck();
      expect(fresh.status, UpdateStatus.available);
      expect(fresh.showBanner, isFalse);
    });

    test('a newer release than the snoozed one shows the banner again',
        () async {
      final p = provider('1.0.3', '1.0.4');
      await p.silentCheck();
      await p.snooze();

      final newer = provider('1.0.3', '1.0.5');
      await newer.silentCheck();
      expect(newer.showBanner, isTrue);
    });

    test('manual check surfaces errors', () async {
      final p = UpdateProvider(
        service: UpdateService(
          apiGet: (_) async => _response(500),
          currentVersion: () async => '1.0.3',
        ),
        installer: UpdateInstaller(),
      );
      await p.checkNow();
      expect(p.status, UpdateStatus.error);
      expect(p.errorMessage, isNotNull);
    });

    test('everything is a no-op off desktop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final p = provider('1.0.3', '1.0.4');
      await p.silentCheck();
      await p.checkNow();
      expect(p.status, UpdateStatus.idle);
      expect(p.showBanner, isFalse);
    });
  });

  group('UpdateInstaller.swapDirs', () {
    test('swaps staging into place and keeps the old install as .old',
        () async {
      final root = await Directory.systemTemp.createTemp('swap-test-');
      addTearDown(() => root.delete(recursive: true));
      final install = Directory('${root.path}/app')..createSync();
      File('${install.path}/bin').writeAsStringSync('old');
      final staging = Directory('${install.path}.staging')..createSync();
      File('${staging.path}/bin').writeAsStringSync('new');
      // A stale rollback dir from a previous update must not block the swap.
      Directory('${install.path}.old').createSync();

      UpdateInstaller.swapDirs(install: install, staging: staging);

      expect(File('${install.path}/bin').readAsStringSync(), 'new');
      expect(File('${install.path}.old/bin').readAsStringSync(), 'old');
      expect(staging.existsSync(), isFalse);
    });
  });
}
