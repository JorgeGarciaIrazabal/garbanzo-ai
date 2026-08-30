import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';
import 'package:garbanzo_ai/features/rooms/widgets/add_agent_dialog.dart';
import 'package:garbanzo_ai/features/tools/models/mcp_tool.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';
import 'package:garbanzo_ai/features/tools/services/tool_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

import 'fake_room_channel.dart';

class _MockRoomService extends Mock implements RoomService {}
class _MockToolService extends Mock implements ToolService {}

final _now = DateTime.utc(2026, 8, 30);

RoomAgent _agent() => RoomAgent(
      id: 'a1',
      roomId: 'r1',
      name: 'Botty',
      model: 'llama3.2',
      provider: 'ollama',
      responseMode: 'mention',
      turnOrder: 0,
      isActive: true,
      isModerator: false,
      createdAt: _now,
    );

Future<ModelList> _models() async => const ModelList(
      models: [
        ModelInfo(
          id: 'llama3.2',
          name: 'Llama 3.2',
          provider: 'ollama',
          supportsTools: true,
        ),
      ],
      defaultModel: 'llama3.2',
    );

Widget _host(Widget page, {ToolProvider? toolProvider}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: toolProvider ?? _buildToolsProvider(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );

ToolProvider _buildToolsProvider() {
  final toolService = _MockToolService();
  when(() => toolService.listAllTools()).thenAnswer(
    (_) async => const [
      MCPTool(serverId: 's1', serverName: 'Search', name: 'web_search'),
    ],
  );
  return ToolProvider(service: toolService);
}

void main() {
  testWidgets(
    'Add button enables once a name is typed (was: stuck disabled forever)',
    (tester) async {
      // The dialog's content column is sized for real screens; the default
      // 800x600 test surface overflows its AlertDialog wrapper.
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = _MockRoomService();
      final room = Room(
        id: 'r1',
        name: 'Room One',
        ownerId: 'me@x.com',
        isPublic: false,
        maxAgentTurnDepth: 3,
        mode: 'chat',
        createdAt: _now,
        updatedAt: _now,
        memberCount: 1,
        agentCount: 0,
        members: const [],
        agents: const [],
      );
      when(() => service.getRoom('r1')).thenAnswer((_) async => room);
      when(() => service.addAgent('r1',
              name: any(named: 'name'),
              model: any(named: 'model'),
              provider: any(named: 'provider'),
              avatar: any(named: 'avatar'),
              systemPrompt: any(named: 'systemPrompt'),
              thinkingLevel: any(named: 'thinkingLevel'),
              responseMode: any(named: 'responseMode'),
              turnOrder: any(named: 'turnOrder'),
              isModerator: any(named: 'isModerator'),
              enabledTools: any(named: 'enabledTools')))
          .thenAnswer((_) async => _agent());
      when(() => service.listMessages('r1'))
          .thenAnswer((_) async => <RoomMessage>[]);

      final provider = RoomProvider(
        service: service,
        // Fake channel so openRoom's socket doesn't dial a real network
        // endpoint from the test harness (same pattern as room_provider_test).
        socketFactory: (id) => RoomSocketService(
          id,
          channelFactory: (_) => FakeRoomChannel(),
          tokenProvider: () async => 'test-token',
          uriBuilder: (_) => Uri.parse('ws://test/$id'),
        ),
      );
      // The Add-agent dialog is only reachable inside an open room — open one
      // so provider.addAgent has a current room to target.
      await provider.openRoom('r1');

      // Open the dialog through the real entry point (showAnimatedDialog →
      // Overlay) so layout matches production instead of a raw Scaffold body.
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAddAgentDialog(
                  context,
                  provider,
                  modelsLoader: _models,
                  templatesLoader: () async => const [],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Model list loads async — wait for it before asserting the button.
      expect(find.text('Llama 3.2'), findsOne);

      var button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Add'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull, reason: 'no name typed yet');

      await tester.enterText(
        find.byType(TextField).first,
        'Research Bot',
      );
      await tester.pumpAndSettle();

      // The regression: the TextEditingController drives no rebuild, so the
      // button stayed disabled even with a valid name.
      button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Add'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull,
          reason: 'typing a name must enable the Add button');

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      verify(
        () => service.addAgent('r1',
            name: any(named: 'name'),
            model: any(named: 'model'),
            provider: any(named: 'provider'),
            avatar: any(named: 'avatar'),
            systemPrompt: any(named: 'systemPrompt'),
            thinkingLevel: any(named: 'thinkingLevel'),
            responseMode: any(named: 'responseMode'),
            turnOrder: any(named: 'turnOrder'),
            isModerator: any(named: 'isModerator'),
            enabledTools: any(named: 'enabledTools')),
      ).called(1);

      provider.dispose();
    },
  );
}