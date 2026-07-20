@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';
import 'package:garbanzo_ai/features/chat/services/folder_writer.dart';

/// Covers the two client-side halves of a delegated workflow (idea 18): the
/// walk that builds the upload snapshot, and the writer that applies the diff
/// back — including the escape guard, which is the security boundary.
void main() {
  late Directory root;
  const reader = FolderReader();
  const writer = FolderWriter();

  setUp(() {
    root = Directory.systemTemp.createTempSync('folder_walk_test');
    File('${root.path}/a.txt').writeAsStringSync('alpha');
    Directory('${root.path}/src').createSync();
    File('${root.path}/src/main.dart').writeAsStringSync('void main() {}');
    Directory('${root.path}/node_modules').createSync();
    File('${root.path}/node_modules/junk.js').writeAsStringSync('noise');
    Directory('${root.path}/.git').createSync();
    File('${root.path}/.git/config').writeAsStringSync('noise');
    File('${root.path}/.env').writeAsStringSync('SECRET=1');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('walk', () {
    test('collects nested files and skips VCS/build noise and dotfiles', () {
      final walk = reader.walk(root.path);
      expect(walk.paths, containsAll(<String>['a.txt', 'src/main.dart']));
      expect(walk.paths, isNot(contains('node_modules/junk.js')));
      expect(walk.paths, isNot(contains('.git/config')));
      expect(walk.paths, isNot(contains('.env')));
      expect(walk.totalBytes, greaterThan(0));
      expect(walk.truncated, isFalse);
    });

    test('skips files above the per-file cap without failing the walk', () {
      final big = File('${root.path}/big.bin')
        ..writeAsBytesSync(List.filled(FolderReader.maxFileBytes + 1, 0));
      addTearDown(big.deleteSync);

      final walk = reader.walk(root.path);
      expect(walk.paths, isNot(contains('big.bin')));
      expect(walk.skipped, contains('big.bin'));
      expect(walk.paths, contains('a.txt'));
    });

    test('stops at the file-count cap and reports truncation', () {
      final walk = reader.walk(root.path, maxFiles: 1);
      expect(walk.paths, hasLength(1));
      expect(walk.truncated, isTrue);
    });

    test('stops at the total-size cap', () {
      final walk = reader.walk(root.path, maxTotalBytes: 1);
      expect(walk.paths, isEmpty);
      expect(walk.truncated, isTrue);
    });
  });

  group('writer', () {
    test('hashFile matches sha256 of the content, null when missing', () {
      expect(
        writer.hashFile(root.path, 'a.txt'),
        sha256.convert(utf8.encode('alpha')).toString(),
      );
      expect(writer.hashFile(root.path, 'nope.txt'), isNull);
    });

    test('writes a new file, creating parent directories', () {
      writer.writeFile(root.path, 'deep/nested/new.txt', utf8.encode('hi'));
      expect(File('${root.path}/deep/nested/new.txt').readAsStringSync(), 'hi');
    });

    test('overwrites an existing file', () {
      writer.writeFile(root.path, 'a.txt', utf8.encode('beta'));
      expect(File('${root.path}/a.txt').readAsStringSync(), 'beta');
    });

    test('deletes a file, and tolerates one already gone', () {
      writer.deleteFile(root.path, 'a.txt');
      expect(File('${root.path}/a.txt').existsSync(), isFalse);
      expect(() => writer.deleteFile(root.path, 'a.txt'), returnsNormally);
    });

    test('refuses to write outside the attached folder', () {
      expect(
        () => writer.writeFile(root.path, '../escaped.txt', utf8.encode('x')),
        throwsA(isA<FolderReadError>()),
      );
      expect(
        () => writer.writeFile(root.path, '/tmp/escaped.txt', utf8.encode('x')),
        throwsA(isA<FolderReadError>()),
      );
      expect(File('${root.parent.path}/escaped.txt').existsSync(), isFalse);
    });

    test('refuses to delete outside the attached folder', () {
      expect(
        () => writer.deleteFile(root.path, '../../etc/passwd'),
        throwsA(isA<FolderReadError>()),
      );
    });
  });
}
