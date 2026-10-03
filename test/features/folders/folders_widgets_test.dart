import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/widgets/tool_bubble_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attach_menu_button.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/pages/folders_page.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/chat_folder_attachments.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_download_button.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_text_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

import 'folders_test_support.dart' show RecordingApi, testFile;

class FakeFolders extends FoldersService {
  FakeFolders() : super(api: RecordingApi());
  bool editable = true;
  bool noFolders = false;
  Completer<void>? secondPage;
  String? saved;
  int? savedRevision;
  bool conflict = false;
  int downloads = 0;
  int attachmentReads = 0;
  String? attachedConversation;
  String? attachedFolder;
  List<VirtualFolder> attachedFolders = [];
  final pendingReads = <String, Completer<List<VirtualFolder>>>{};
  String? createdName;
  String? savedDescription;
  @override
  Future<VirtualFolder> create(String name, {String description = ''}) async {
    createdName = name; savedDescription = description; noFolders = false;
    folder = folder.copyWith(name: name, description: description);
    return folder;
  }
  @override
  Future<VirtualFolder> update(String id, {String? name, String? description}) async {
    savedDescription = description;
    folder = folder.copyWith(name: name ?? folder.name, description: description ?? folder.description);
    return folder;
  }
  var folder = VirtualFolder(id: 'folder', name: 'Project files', description: 'Project source material', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
  @override
  Future<List<VirtualFolder>> list() async => noFolders ? [] : [folder];
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
  Future<void> attach(String conversationId, String folderId) async { attachedConversation = conversationId; attachedFolder = folderId; attachedFolders = [folder]; }
  @override
  Future<List<VirtualFolder>> attached(String conversationId) async { attachmentReads++; return pendingReads[conversationId]?.future ?? attachedFolders; }
  @override
  Future<void> download({required String folderId, String? fileId, required String filename, required String mediaType, required String title}) async { downloads++; }
}
Widget app(Widget child) => MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child));

Widget composer(BuildContext context, Future<void> Function()? attach, Widget chips) => Column(
  children: [chips, AttachMenuButton(enabled: true, existingNames: () => {}, onAdded: (_) {}, onPickSavedFolder: attach)],
);

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
  testWidgets('empty saved-folder picker opens folder browser and refreshes on return', (tester) async {
    final service = FakeFolders()..noFolders = true;
    final router = GoRouter(initialLocation: '/chat', routes: [
      GoRoute(path: '/chat', builder: (_, _) => Scaffold(body: ChatFolderAttachments(
        conversationId: 'conversation', isSending: false, ensureConversation: () async => 'conversation',
        builder: composer, service: service))),
      GoRoute(path: '/folders', builder: (_, _) => FoldersPage(service: service)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Attach photos or files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach saved folder'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Create a folder in Folders, then attach it here.'), findsOneWidget);
    await tester.tap(find.text('Open folders'));
    await tester.pumpAndSettle();
    expect(find.byType(FoldersPage), findsOneWidget);
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'Created from paperclip');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final beforeReturn = service.attachmentReads;
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(FoldersPage), findsNothing);
    expect(service.attachmentReads, greaterThan(beforeReturn));
    expect(find.text('Open folders'), findsNothing);
    await tester.tap(find.byTooltip('Attach photos or files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach saved folder'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Created from paperclip'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('folder metadata is entered manually, saved and editable', (tester) async {
    final service = FakeFolders();
    await tester.pumpWidget(app(FoldersPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('folder_description'))).controller!.text, 'Project source material');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('folder_description'))).maxLength, 2000);
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'Sources');
    await tester.enterText(find.byKey(const ValueKey('folder_description')), 'Use these for comparisons');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(service.folder.name, 'Sources');
    expect(service.savedDescription, 'Use these for comparisons');
    expect(find.text('Use these for comparisons'), findsOneWidget);
    expect(find.textContaining('The AI uses this context'), findsOneWidget);
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'New project');
    await tester.enterText(find.byKey(const ValueKey('folder_description')), 'A new project context');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(service.createdName, 'New project');
    expect(service.savedDescription, 'A new project context');
    expect(find.text('A new project context'), findsOneWidget);
  });
  testWidgets('late old-chat folder reads cannot replace the current chips and landing clears them', (tester) async {
    final service = FakeFolders();
    service.pendingReads['old'] = Completer<List<VirtualFolder>>();
    service.pendingReads['new'] = Completer<List<VirtualFolder>>();
    Future<String> ensure() async => 'new';
    Widget attachments(String? id) => app(ChatFolderAttachments(conversationId: id, isSending: false, builder: composer, ensureConversation: ensure, service: service));
    await tester.pumpWidget(attachments('old'));
    await tester.pump();
    await tester.pumpWidget(attachments('new'));
    service.pendingReads['new']!.complete([service.folder.copyWith(name: 'New sources')]);
    await tester.pumpAndSettle();
    expect(find.text('New sources'), findsOneWidget);
    service.pendingReads['old']!.complete([service.folder.copyWith(name: 'Old sources')]);
    await tester.pumpAndSettle();
    expect(find.text('Old sources'), findsNothing);
    expect(find.text('New sources'), findsOneWidget);
    await tester.pumpWidget(attachments(null));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
  });
  testWidgets('choosing a folder ensures a conversation before attaching', (tester) async {
    final service = FakeFolders();
    var ensured = false;
    await tester.pumpWidget(app(ChatFolderAttachments(conversationId: null, isSending: false,
      builder: composer, ensureConversation: () async { ensured = true; return 'new-chat'; }, service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Attach saved folder'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    await tester.tap(find.byTooltip('Attach photos or files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach saved folder')); await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(ensured, isFalse);
    await tester.tap(find.text('Project files')); await tester.pumpAndSettle();
    expect(ensured, isTrue); expect(service.attachedConversation, 'new-chat'); expect(service.attachedFolder, 'folder');
  });
  testWidgets('chat attachments refresh when streaming completes', (tester) async {
    final service = FakeFolders();
    Future<String> ensure() async => 'conversation';
    await tester.pumpWidget(app(ChatFolderAttachments(conversationId: 'conversation', isSending: true, builder: composer, ensureConversation: ensure, service: service)));
    await tester.pumpAndSettle(); expect(service.attachmentReads, 1);
    service.attachedFolders = [service.folder];
    await tester.pumpWidget(app(ChatFolderAttachments(conversationId: 'conversation', isSending: false, builder: composer, ensureConversation: ensure, service: service)));
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
