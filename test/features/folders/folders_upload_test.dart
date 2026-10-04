import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/pages/folders_page.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

import 'folders_test_support.dart';

class _Uploads extends FoldersService {
  _Uploads() : super(api: RecordingApi());
  final stored = <FolderFile>[testFile];
  final copies = <bool>[];
  final savedNames = <String>[];
  int? replacedRevision;
  Uint8List? replacedBytes;
  bool staleReplacement = false;
  bool failNextFile = false;
  @override
  Future<List<VirtualFolder>> list() async => [
    VirtualFolder(id: 'folder', name: 'Sources', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)),
  ];
  @override
  Future<List<FolderFile>> files(String id) async => List.of(stored);
  @override
  Future<FolderFile> upload(String id, String path, Uint8List bytes, {bool keepBoth = false}) async {
    copies.add(keepBoth);
    if (stored.any((f) => f.path == path) && !keepBoth) {
      throw const FolderException(409, 'Already exists');
    }
    if (failNextFile && path == 'other.txt') {
      throw const FolderException(413, 'Storage limit reached');
    }
    final name = keepBoth ? 'notes (2).txt' : path;
    final saved = testFile.copyWith(id: name, path: name, sizeBytes: bytes.length, revision: 1);
    stored.add(saved);
    savedNames.add(name);
    return saved;
  }
  @override
  Future<FolderFile> replaceFile(FolderFile file, Uint8List bytes) async {
    replacedRevision = file.revision;
    if (staleReplacement) throw const FolderException(409, 'File changed since you selected it');
    replacedBytes = bytes;
    final replaced = file.copyWith(revision: file.revision + 1, sizeBytes: bytes.length);
    stored[stored.indexWhere((f) => f.id == file.id)] = replaced;
    return replaced;
  }
}

Future<void> _openUpload(WidgetTester tester, _Uploads service, {bool multiple = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FoldersPage(service: service, pickFiles: () async => FilePickerResult([
      PlatformFile(name: 'notes.txt', size: 3, bytes: Uint8List.fromList([0, 255, 65])),
      if (multiple) PlatformFile(name: 'other.txt', size: 1, bytes: Uint8List.fromList([66])),
    ])),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Upload files'));
  // The progress indicator stays active while the duplicate dialog is open.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('File already exists'), findsOneWidget);
  expect(find.text('Replace'), findsOneWidget);
  expect(find.text('Keep both'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('Replace uploads original bytes against the selected revision', (tester) async {
    final service = _Uploads();
    await _openUpload(tester, service);
    expect(service.replacedBytes, isNull);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(service.replacedRevision, 7);
    expect(service.replacedBytes, [0, 255, 65]);
    expect(service.stored, hasLength(1));
    expect(service.stored.single.id, testFile.id);
    expect(find.text('notes.txt'), findsOneWidget);
  });

  testWidgets('Keep both preserves the original and displays the new copy', (tester) async {
    final service = _Uploads();
    await _openUpload(tester, service);
    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect(service.copies, [false, true]);
    expect(service.replacedBytes, isNull);
    expect(service.stored.first, testFile);
    expect(find.text('notes (2).txt'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
  });

  testWidgets('Cancel skips the duplicate and continues other selected files', (tester) async {
    final service = _Uploads();
    await _openUpload(tester, service, multiple: true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.replacedBytes, isNull);
    expect(service.savedNames, ['other.txt']);
    expect(service.stored.first, testFile);
    expect(find.text('other.txt'), findsOneWidget);
  });

  testWidgets('A stale replacement shows an error without overwriting', (tester) async {
    final service = _Uploads()..staleReplacement = true;
    await _openUpload(tester, service);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(service.replacedBytes, isNull);
    expect(service.stored.single, testFile);
    expect(find.textContaining('File changed since you selected it'), findsOneWidget);
  });

  testWidgets('Successful copies remain visible when another upload fails', (tester) async {
    final service = _Uploads()..failNextFile = true;
    await _openUpload(tester, service, multiple: true);
    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect(find.text('notes (2).txt'), findsOneWidget);
    expect(find.textContaining('other.txt: Storage limit reached'), findsOneWidget);
  });
}
