@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake ChatService that scripts the stream and records client-tool-result
/// posts so we can assert the client served a folder read locally.
class _FakeChatService extends ChatService {
  _FakeChatService() : super.forTesting();

  /// A fresh controller per stream so tests can close one send and start
  /// another (ChatProvider blocks concurrent sends while _isSending).
  late StreamController<ChatResponseChunk> controller;
  final List<({String conversationId, Map<String, dynamic> payload})> posted =
      [];
  bool? lastHasClientFolder;

  final _conversation = Conversation(
    id: 'conv-1',
    title: 'Test',
    model: 'llama3.2',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    messages: const [],
  );

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 50,
  }) async =>
      ConversationList(items: [_conversation], total: 1, page: 1, pageSize: 50);

  @override
  Future<Conversation> getConversation(
    String conversationId, {
    int? messageLimit,
  }) async =>
      _conversation;

  @override
  Stream<ChatResponseChunk> streamChatResponse(
    String conversationId,
    String message, {
    List<ChatAttachment> attachments = const [],
    double temperature = 0.7,
    int? maxTokens,
    double? topP,
    bool hasClientFolder = false,
  }) {
    lastHasClientFolder = hasClientFolder;
    controller = StreamController<ChatResponseChunk>();
    return controller.stream;
  }

  @override
  Future<void> postClientToolResult(
    String conversationId,
    Map<String, dynamic> payload,
  ) async {
    posted.add((conversationId: conversationId, payload: payload));
  }
}

ChatResponseChunk _readRequest(String path) => ChatResponseChunk(
      type: 'client_tool_request',
      metadata: {
        'client_tool_request': {
          'tool_call_id': 'tc-1',
          'tool_name': 'read_file',
          'args': {'path': path},
        },
      },
    );

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folder = Directory.systemTemp.createTempSync('cp_folder_test');
    File('${folder.path}/notes.txt').writeAsStringSync('hello from the folder');
  });

  tearDown(() => folder.deleteSync(recursive: true));

  Future<ChatProvider> openProvider(_FakeChatService service) async {
    final provider = ChatProvider(chatService: service);
    await provider.loadConversation('conv-1');
    return provider;
  }

  test('attach/clear folder is reflected and persisted', () async {
    final service = _FakeChatService();
    final provider = await openProvider(service);

    await provider.attachClientFolder('conv-1', folder.path);
    expect(provider.clientFolderFor('conv-1'), folder.path);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('client_folders'), contains(folder.path));

    await provider.clearClientFolder('conv-1');
    expect(provider.clientFolderFor('conv-1'), isNull);
  });

  test('sends has_client_folder only when a folder is attached', () async {
    final service = _FakeChatService();
    final provider = await openProvider(service);

    await provider.sendMessage('hi');
    expect(service.lastHasClientFolder, isFalse);
    // End the first stream so the provider is free to send again.
    await service.controller.close();
    await _pump();

    await provider.attachClientFolder('conv-1', folder.path);
    await provider.sendMessage('again');
    expect(service.lastHasClientFolder, isTrue);
  });

  test('serves a read_file request by reading locally and posting bytes',
      () async {
    final service = _FakeChatService();
    final provider = await openProvider(service);
    await provider.attachClientFolder('conv-1', folder.path);

    await provider.sendMessage('read notes');
    service.controller.add(_readRequest('notes.txt'));
    await _pump();

    expect(service.posted, hasLength(1));
    final payload = service.posted.single.payload;
    expect(payload['tool_call_id'], 'tc-1');
    expect(payload['ok'], isTrue);
    expect(payload['filename'], 'notes.txt');
    expect(
      utf8.decode(base64Decode(payload['data'] as String)),
      'hello from the folder',
    );
  });

  test('reports an error when the path escapes the folder', () async {
    final service = _FakeChatService();
    final provider = await openProvider(service);
    await provider.attachClientFolder('conv-1', folder.path);

    await provider.sendMessage('read secret');
    service.controller.add(_readRequest('../../etc/passwd'));
    await _pump();

    expect(service.posted, hasLength(1));
    final payload = service.posted.single.payload;
    expect(payload['ok'], isFalse);
    expect((payload['error'] as String).toLowerCase(), contains('escape'));
  });
}
