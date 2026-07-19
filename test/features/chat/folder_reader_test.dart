@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';

void main() {
  late Directory root;
  const reader = FolderReader();

  setUp(() {
    root = Directory.systemTemp.createTempSync('folder_reader_test');
    File('${root.path}/notes.txt').writeAsStringSync('hello world');
    Directory('${root.path}/src').createSync();
    File('${root.path}/src/main.dart').writeAsStringSync('void main() {}');
    File('${root.path}/.secret').writeAsStringSync('hidden');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('safeResolve', () {
    test('rejects traversal, absolute, and parent escapes', () {
      expect(reader.safeResolve(root.path, '../../etc/passwd'), isNull);
      expect(reader.safeResolve(root.path, '/etc/passwd'), isNull);
      expect(reader.safeResolve(root.path, 'src/../../../etc/passwd'), isNull);
    });

    test('allows nested paths inside the root', () {
      final resolved = reader.safeResolve(root.path, 'src/main.dart');
      expect(resolved, isNotNull);
      expect(resolved, endsWith('main.dart'));
    });

    test('rejects a symlink escaping the root', () {
      final outside = File('${root.parent.path}/outside_${root.uri.pathSegments.last}.txt')
        ..writeAsStringSync('top secret');
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync();
      });
      try {
        Link('${root.path}/link.txt').createSync(outside.path);
      } on FileSystemException {
        return; // symlinks unsupported on this platform
      }
      expect(reader.safeResolve(root.path, 'link.txt'), isNull);
    });
  });

  group('readFile', () {
    test('reads a file inside the folder', () {
      final result = reader.readFile(root.path, 'notes.txt');
      expect(String.fromCharCodes(result.bytes), 'hello world');
      expect(result.filename, 'notes.txt');
    });

    test('throws on an escaping path', () {
      expect(
        () => reader.readFile(root.path, '../../etc/passwd'),
        throwsA(isA<FolderReadError>()),
      );
    });

    test('throws on a missing file', () {
      expect(
        () => reader.readFile(root.path, 'nope.txt'),
        throwsA(isA<FolderReadError>()),
      );
    });
  });

  group('listDir', () {
    test('lists entries and skips dotfiles', () {
      final entries = reader.listDir(root.path, '.');
      final paths = entries.map((e) => e['path']).toSet();
      expect(paths, contains('notes.txt'));
      expect(paths, contains('src'));
      expect(paths, isNot(contains('.secret')));
      final srcEntry = entries.firstWhere((e) => e['path'] == 'src');
      expect(srcEntry['is_dir'], isTrue);
    });

    test('throws on an escaping path', () {
      expect(
        () => reader.listDir(root.path, '../..'),
        throwsA(isA<FolderReadError>()),
      );
    });
  });
}
