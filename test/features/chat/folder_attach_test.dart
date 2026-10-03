import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attach_menu_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/folder_chip.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garbanzo_ai/core/auth_state.dart';
import 'package:garbanzo_ai/core/router.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/style_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/style_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_input_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_page.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/message_composer.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';

import '../folders/folders_test_support.dart' show RecordingApi;

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

class _SignedIn extends AuthState {
  @override
  bool get loggedIn => true;
  @override
  Future<void> ensureReady() async {}
}

class _ChatService extends ChatService {
  _ChatService() : super.forTesting();
  @override
  Future<ConversationList> listConversations({int page = 1, int pageSize = 20, bool silent = false}) async => const ConversationList(items: [], total: 0, page: 1, pageSize: 20);
  @override
  Future<ModelList> listModels() async => const ModelList(models: []);
}
class _Styles extends StyleService {
  _Styles() : super.forTesting();
  @override
  Future<List<Style>> listStyles() async => [];
}
class _Prompts extends SystemPromptProvider {
  @override
  Future<void> refresh({String? locale}) async {}
}
class _Chat extends ChatProvider {
  _Chat() : super(chatService: _ChatService());
  Conversation? conversation;
  final loaded = <String>[];
  int sent = 0;
  void enterLanding() { conversation = null; notifyListeners(); }
  @override
  Conversation? get currentConversation => conversation;
  @override
  Future<void> loadConversation(String id) async {
    loaded.add(id);
    conversation = Conversation(id: id, model: 'model', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
    notifyListeners();
  }
}
class _Folders extends FoldersService {
  _Folders() : super(api: RecordingApi());
  final folder = VirtualFolder(id: 'saved', name: 'Saved sources', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
  String? attachedTo;
  Completer<void>? attachPending;
  Completer<void>? detachPending;
  @override
  Future<List<VirtualFolder>> list() async => [folder];
  @override
  Future<List<VirtualFolder>> attached(String id) async => id == attachedTo ? [folder] : [];
  @override
  Future<void> attach(String id, String folderId) async {
    await attachPending?.future;
    attachedTo = id;
  }
  @override
  Future<void> detach(String id, String folderId) async {
    await detachPending?.future;
    attachedTo = null;
  }
}

// Mount the actual composer with production route pages/keys, replacing only
// the sidebar, history and background polling unrelated to this regression.
class _ComposerRoute extends StatefulWidget {
  const _ComposerRoute({required this.conversationId, required this.folders});
  final String? conversationId;
  final FoldersService folders;
  @override
  State<_ComposerRoute> createState() => _ComposerRouteState();
}
class _ComposerRouteState extends State<_ComposerRoute> {
  @override
  void didUpdateWidget(covariant _ComposerRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != oldWidget.conversationId && widget.conversationId != context.read<ChatProvider>().currentConversation?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.conversationId == null) {
          (context.read<ChatProvider>() as _Chat).enterLanding();
        } else {
          context.read<ChatProvider>().loadConversation(widget.conversationId!);
        }
      });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [const Spacer(), ChatInputWidget(
      foldersService: widget.folders,
      onSend: (_, _) => (context.read<ChatProvider>() as _Chat).sent++,
      ensureFolderConversation: () async {
        final chat = context.read<ChatProvider>();
        if (chat.currentConversation == null) {
          await chat.loadConversation('created-chat');
          if (context.mounted) context.go('/chat/created-chat');
        }
        return chat.currentConversation!.id;
      },
    )]),
  );
}

void main() {
  testWidgets('saved-folder chat creation preserves typed draft and staged files across the real chat route keys', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final chat = _Chat();
    final folders = _Folders()..attachPending = Completer<void>();
    final models = ModelProvider(chatService: _ChatService());
    final styles = StyleProvider(styleService: _Styles());
    final prompts = _Prompts();
    final settings = SettingsProvider();
    final topics = TopicDiscoveryProvider();
    final tools = ToolProvider();
    final auth = _SignedIn();
    final production = buildRouter(auth);
    final chatRoutes = production.configuration.routes.whereType<GoRoute>().where((route) => route.path == '/chat' || route.path == '/chat/:conversationId');
    final router = GoRouter(initialLocation: '/chat', routes: [
      for (final route in chatRoutes)
        GoRoute(path: route.path, pageBuilder: (context, state) {
          final page = route.pageBuilder!(context, state) as NoTransitionPage;
          final chatPage = page.child as ChatPage;
          return NoTransitionPage(key: page.key,
            child: _ComposerRoute(conversationId: chatPage.conversationId, folders: folders));
        }),
    ]);
    addTearDown(router.dispose);
    addTearDown(production.dispose);
    addTearDown(auth.dispose);
    for (final provider in [chat, models, styles, prompts, settings, topics, tools]) { addTearDown(provider.dispose); }
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ChatProvider>.value(value: chat),
      ChangeNotifierProvider<ModelProvider>.value(value: models),
      ChangeNotifierProvider<StyleProvider>.value(value: styles),
      ChangeNotifierProvider<SystemPromptProvider>.value(value: prompts),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<TopicDiscoveryProvider>.value(value: topics),
      ChangeNotifierProvider<ToolProvider>.value(value: tools),
    ], child: MaterialApp.router(routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales)));
    await tester.pumpAndSettle();
    final composerBefore = tester.state(find.byType(ChatInputWidget));
    await tester.enterText(find.byType(TextField), 'Compare these sources');
    tester.widget<AttachMenuButton>(find.byType(AttachMenuButton)).onAdded([
      ChatAttachment(name: 'notes.txt', mimeType: 'text/plain', type: AttachmentType.document, bytes: Uint8List.fromList([65])),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.byTooltip('Attach photos or files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach saved folder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Saved sources'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(folders.attachedTo, isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('send_button'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chat.sent, 0);
    expect(find.text('Compare these sources'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    folders.attachPending!.complete();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/chat/created-chat');
    expect(folders.attachedTo, 'created-chat');
    expect(tester.state(find.byType(ChatInputWidget)), same(composerBefore));
    expect(find.text('Compare these sources'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.descendant(of: find.byType(MessageComposer), matching: find.widgetWithText(InputChip, 'Saved sources')), findsOneWidget);
    expect(find.text('Attach saved folder'), findsNothing);
    folders.detachPending = Completer<void>();
    await tester.tap(find.byTooltip('Detach folder'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(folders.attachedTo, 'created-chat');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('send_button'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chat.sent, 0);
    expect(find.text('Compare these sources'), findsOneWidget);
    folders.detachPending!.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Saved sources'), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('send_button'))).onPressed, isNotNull);
    router.go('/chat/other-chat');
    await tester.pumpAndSettle();
    expect(chat.loaded.last, 'other-chat');
    expect(chat.currentConversation?.id, 'other-chat');
    expect(find.widgetWithText(InputChip, 'Saved sources'), findsNothing);
    router.go('/chat');
    await tester.pumpAndSettle();
    expect(find.text('Compare these sources'), findsNothing);
    expect(find.text('notes.txt'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Ready');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await tester.pump();
    expect(chat.sent, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  group('FolderChip', () {
    testWidgets('shows the folder basename and calls onRemove', (tester) async {
      var removed = false;
      await tester.pumpWidget(
        _wrap(
          FolderChip(
            folderPath: '/home/me/projects/garbanzo',
            onRemove: () => removed = true,
          ),
        ),
      );

      // The scope label carries the last path segment, not the full path.
      expect(find.textContaining('garbanzo'), findsOneWidget);
      expect(find.textContaining('/home/me'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      expect(removed, isTrue);
    });
  });

  group('AttachMenuButton folder option', () {
    for (final width in [390.0, 1200.0]) {
      testWidgets('saved folder is invoked through paperclip at width $width on mobile', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var picked = false;
        var livePicked = false;
        await tester.pumpWidget(_wrap(AttachMenuButton(
          enabled: true, existingNames: () => {}, onAdded: (_) {},
          onPickSavedFolder: () async => picked = true,
          onPickFolder: () async => livePicked = true,
        )));
        expect(find.text('Attach saved folder'), findsNothing);
        await tester.tap(find.byTooltip('Attach photos or files'));
        await tester.pumpAndSettle();
        expect(find.text('Photos'), findsOneWidget);
        expect(find.text('Files'), findsOneWidget);
        expect(find.text('Folder'), findsNothing);
        if (width < 600) {
          expect(find.byType(BottomSheet), findsOneWidget);
        } else {
          expect(find.widgetWithText(MenuItemButton, 'Attach saved folder'), findsOneWidget);
        }
        await tester.tap(find.text('Attach saved folder'));
        await tester.pumpAndSettle();
        expect(picked, isTrue);
        expect(livePicked, isFalse);
        expect(find.byType(BottomSheet), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('shows Folder option on desktop when onPickFolder is set', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var picked = false;
      await tester.pumpWidget(
        _wrap(
          AttachMenuButton(
            enabled: true,
            existingNames: () => <String>{},
            onAdded: (_) {},
            onPickFolder: () async => picked = true,
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      final folderItem = find.text('Folder');
      expect(folderItem, findsOneWidget);
      await tester.tap(folderItem);
      await tester.pumpAndSettle();
      expect(picked, isTrue);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('hides Folder option when onPickFolder is null', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          AttachMenuButton(
            enabled: true,
            existingNames: () => <String>{},
            onAdded: (List<ChatAttachment> _) {},
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Folder'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
