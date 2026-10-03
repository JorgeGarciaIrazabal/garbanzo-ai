import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/pages/folders_page.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/chat_folders_bar.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_download_button.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_text_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

import 'folders_test_support.dart' show RecordingApi, testFile;

class FakeFolders extends FoldersService {
  FakeFolders() : super(api: RecordingApi());
  bool editable = true;
  Completer<void>? secondPage;
  String? saved;
  int? savedRevision;
  bool conflict = false;
  int downloads = 0;
  int attachmentReads = 0;
  String? attachedConversation;
  String? attachedFolder;
  List<VirtualFolder> attachedFolders = [];
  final folder = VirtualFolder(id: 'folder', name: 'Project files', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
  @override
  Future<List<VirtualFolder>> list() async => [folder];
  @override
  Future<List<FolderFile>> files(String id) async => [testFile];
  @override
  Future<FolderText> text(FolderFile file, {int offset = 0}) async {
    if (offset > 0 && secondPage != null) await secondPage!.future;
    return FolderText(file: file, text: offset == 0 ? 'first ' : 'second', offset: offset, nextOffset: offset == 0 ? 6 : null, totalChars: 12, editable: editable);
  }
  @override
  Future<FolderFile> saveText(FolderFile file, String content) async {
    saved = content; savedRevision = file.revision;
    if (conflict) throw const FolderException(409, 'revision changed');
    return file.copyWith(revision: file.revision + 1);
  }
  @override
  Future<void> attach(String conversationId, String folderId) async { attachedConversation = conversationId; attachedFolder = folderId; }
  @override
  Future<List<VirtualFolder>> attached(String conversationId) async { attachmentReads++; return attachedFolders; }
  @override
  Future<void> download({required String folderId, String? fileId, required String filename, required String mediaType, required String title}) async { downloads++; }
}
Widget app(Widget child) => MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child));

void main() {
  testWidgets('editable preview loads all pages before Save and retains revision', (tester) async {
    final service = FakeFolders()..secondPage = Completer<void>();
    await tester.pumpWidget(app(FolderTextDialog(service: service, folderId: 'folder', file: testFile)));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    service.secondPage!.complete();
    await tester.pumpAndSettle();
    expect(find.text('first second'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(service.saved, 'first second'); expect(service.savedRevision, 7);
  });
  testWidgets('extracted document preview is read-only and can load next page', (tester) async {
    final service = FakeFolders()..editable = false;
    await tester.pumpWidget(app(FolderTextDialog(service: service, folderId: 'folder', file: testFile)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.text('Read more')); await tester.pumpAndSettle();
    expect(find.text('first second'), findsOneWidget);
    expect(find.text('Read more'), findsNothing);
  });
  testWidgets('revision conflict preserves edits and blocks retry with stale revision', (tester) async {
    final service = FakeFolders()..conflict = true;
    await tester.pumpWidget(app(FolderTextDialog(service: service, folderId: 'folder', file: testFile)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my edits');
    await tester.tap(find.widgetWithText(FilledButton, 'Save')); await tester.pumpAndSettle();
    expect(find.text('my edits'), findsOneWidget);
    expect(find.textContaining('changed since you opened'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
  });
  testWidgets('folders list fits a phone and exposes stored files', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(FoldersPage(service: FakeFolders()))); await tester.pumpAndSettle();
    expect(find.text('Project files'), findsOneWidget); expect(find.text('notes.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('choosing a folder ensures a conversation before attaching', (tester) async {
    final service = FakeFolders();
    var ensured = false;
    await tester.pumpWidget(app(ChatFoldersBar(conversationId: null, isSending: false,
      ensureConversation: () async { ensured = true; return 'new-chat'; }, service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach folder')); await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(ensured, isFalse);
    await tester.tap(find.text('Project files')); await tester.pumpAndSettle();
    expect(ensured, isTrue); expect(service.attachedConversation, 'new-chat'); expect(service.attachedFolder, 'folder');
  });
  testWidgets('chat attachments refresh when streaming completes', (tester) async {
    final service = FakeFolders();
    Future<String> ensure() async => 'conversation';
    await tester.pumpWidget(app(ChatFoldersBar(conversationId: 'conversation', isSending: true, ensureConversation: ensure, service: service)));
    await tester.pumpAndSettle(); expect(service.attachmentReads, 1);
    service.attachedFolders = [service.folder];
    await tester.pumpWidget(app(ChatFoldersBar(conversationId: 'conversation', isSending: false, ensureConversation: ensure, service: service)));
    await tester.pumpAndSettle(); expect(service.attachmentReads, 2); expect(find.text('Project files'), findsOneWidget);
  });
  testWidgets('download requires a click and is visible in persisted tool bubble', (tester) async {
    final service = FakeFolders();
    final download = {'folder_id': 'folder', 'file_id': 'file', 'filename': 'notes.txt', 'media_type': 'text/plain'};
    await tester.pumpWidget(app(FolderDownloadButton(download: download, service: service))); await tester.pumpAndSettle();
    expect(service.downloads, 0);
    await tester.tap(find.text('Download: notes.txt')); await tester.pumpAndSettle(); expect(service.downloads, 1);
    for (final nested in [false, true]) {
      final meta = {'tool_name': 'virtual_folders', 'tool_call_id': 'call', 'result': {'ok': true, 'action': 'download', 'download': download}};
      await tester.pumpWidget(app(ToolBubbleWidget(message: ChatMessage(id: 'result', role: 'tool_result', content: '', createdAt: DateTime.utc(2026), metadata: nested ? {'tool_result': meta} : meta))));
      await tester.pumpAndSettle(); expect(find.text('Download: notes.txt'), findsOneWidget);
    }
  });
}
