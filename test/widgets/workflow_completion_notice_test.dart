import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/workflow_run.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/workflow_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/workflow_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/workflow_completion_notice.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class _ChatService extends ChatService {
  _ChatService() : super.forTesting();
  @override
  Future<ConversationList> listConversations({
    int page = 1, int pageSize = 50, bool silent = false, String kind = 'all',
  }) async => ConversationList(items: const [], total: 0, page: page, pageSize: pageSize);
}

class _WorkflowService extends WorkflowService {
  _WorkflowService(this.runs) : super.forTesting();
  final List<WorkflowRun> runs;
  bool failNextLoad = false;
  @override
  Future<List<WorkflowRun>> listForConversation(String conversationId) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('Network request failed');
    }
    return runs.where((run) => run.conversationId == conversationId).toList();
  }
}

WorkflowRun _run(String id, {int epoch = 31, String status = 'done'}) => WorkflowRun(
  id: id,
  userId: 'owner',
  conversationId: 'conversation',
  sessionEpoch: epoch,
  status: status,
  instruction: 'Research heating systems',
  summary: 'Saved finding: ground-source performance was 3.18 COP.',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Conversation _conversation({int epoch = 31}) => Conversation(
  id: 'conversation',
  model: 'test',
  isPrimary: true,
  sessionEpoch: epoch,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  messages: const [],
);

Widget _app(WorkflowProvider provider, {int epoch = 31}) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(children: [
            Expanded(child: ListView.builder(
              itemCount: 100,
              itemBuilder: (_, i) => Text('Later conversation message $i'),
            )),
            WorkflowCompletionNotice(conversation: _conversation(epoch: epoch)),
            const TextField(),
          ]),
        ),
      ),
    );

void main() {
  late ChatProvider chat;
  late WorkflowProvider provider;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    chat = ChatProvider(chatService: _ChatService());
    provider = WorkflowProvider(chat: chat, service: _WorkflowService([_run('private-run')]));
  });
  tearDown(() { provider.dispose(); chat.dispose(); });

  testWidgets('completion remains visible after many messages and opens saved result', (tester) async {
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_notice')), findsOneWidget);
    expect(tester.getBottomLeft(find.byKey(const ValueKey('workflow_completion_notice'))).dy,
        lessThan(600));
    await tester.tap(find.byKey(const ValueKey('workflow_completion_view')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3.18 COP'), findsWidgets);
    expect(find.textContaining('private-run'), findsNothing);
  });

  testWidgets('dismissal persists when provider and app are recreated', (tester) async {
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workflow_completion_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_notice')), findsNothing);
    final restored = WorkflowProvider(chat: chat, service: _WorkflowService([_run('private-run')]));
    addTearDown(restored.dispose);
    await tester.pumpWidget(_app(restored));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_notice')), findsNothing);
  });

  testWidgets('a fresh primary epoch hides an older completion', (tester) async {
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_notice')), findsOneWidget);
    await tester.pumpWidget(_app(provider, epoch: 32));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_notice')), findsNothing);
  });

  testWidgets('a failed initial load shows retry and recovers a buried result', (tester) async {
    provider.dispose();
    final service = _WorkflowService([_run('saved')])..failNextLoad = true;
    provider = WorkflowProvider(chat: chat, service: service);
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_load_error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workflow_completion_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow_completion_load_error')), findsNothing);
    expect(find.byKey(const ValueKey('workflow_completion_notice')), findsOneWidget);
  });

  test('more than 200 explicit dismissals never resurrect older results after restart', () async {
    provider.dispose();
    final runs = List.generate(201, (i) => _run('finished-$i'));
    provider = WorkflowProvider(chat: chat, service: _WorkflowService(runs));
    await provider.loadForConversation('conversation');
    for (final run in runs) { await provider.dismissCompletion(run.id); }
    expect(provider.pendingCompletionFor('conversation', sessionEpoch: 31), isNull);
    final restored = WorkflowProvider(chat: chat, service: _WorkflowService(runs));
    addTearDown(restored.dispose);
    await restored.loadForConversation('conversation');
    expect(restored.pendingCompletionFor('conversation', sessionEpoch: 31), isNull);
  });

  test('running and other-conversation runs are excluded; next result remains after dismiss', () async {
    provider.dispose();
    provider = WorkflowProvider(chat: chat, service: _WorkflowService([
      _run('running', status: 'running'),
      _run('completed'),
      _run('failed', status: 'error'),
      _run('old', epoch: 30),
    ]));
    await provider.loadForConversation('conversation');
    expect(provider.pendingCompletionFor('other'), isNull);
    final first = provider.pendingCompletionFor('conversation', sessionEpoch: 31)!;
    expect(first.id, isNot('running'));
    await provider.dismissCompletion(first.id);
    final next = provider.pendingCompletionFor('conversation', sessionEpoch: 31)!;
    expect(next.id, isNot(first.id));
    expect(next.id, isNot('old'));
  });
}
