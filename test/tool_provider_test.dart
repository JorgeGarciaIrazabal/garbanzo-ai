import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/tools/models/mcp_tool.dart';
import 'package:garbanzo_ai/features/tools/providers/tool_provider.dart';
import 'package:garbanzo_ai/features/tools/services/tool_service.dart';
import 'package:mocktail/mocktail.dart';

class MockToolService extends Mock implements ToolService {}

void main() {
  group('ToolProvider', () {
    late MockToolService service;
    late ToolProvider provider;

    setUp(() {
      service = MockToolService();
      provider = ToolProvider(service: service);
    });

    test('load populates tools on success', () async {
      when(() => service.listAllTools()).thenAnswer(
        (_) async => const [
          MCPTool(
            serverId: 's1',
            serverName: 'filesystem',
            name: 'read_file',
            description: 'Read a file',
          ),
          MCPTool(
            serverId: 's1',
            serverName: 'filesystem',
            name: 'write_file',
          ),
        ],
      );

      expect(provider.isLoaded, isFalse);
      await provider.load();
      expect(provider.isLoaded, isTrue);
      expect(provider.tools.length, 2);
      expect(provider.error, isNull);

      final grouped = provider.toolsByServer;
      expect(grouped.keys, contains('filesystem'));
      expect(grouped['filesystem']!.length, 2);
    });

    test('load sets error on failure', () async {
      when(() => service.listAllTools())
          .thenThrow(Exception('no backend'));

      await provider.load();
      expect(provider.error, isNotNull);
      expect(provider.tools, isEmpty);
      expect(provider.isLoaded, isFalse);
    });

    test('load is idempotent once loaded (no second call)', () async {
      when(() => service.listAllTools()).thenAnswer(
        (_) async => const [
          MCPTool(serverId: 's', serverName: 'sv', name: 'n'),
        ],
      );

      await provider.load();
      await provider.load();
      verify(() => service.listAllTools()).called(1);
    });

    test('load(force: true) re-fetches after initial load', () async {
      when(() => service.listAllTools()).thenAnswer(
        (_) async => const [
          MCPTool(serverId: 's', serverName: 'sv', name: 'n'),
        ],
      );

      await provider.load();
      await provider.load(force: true);
      verify(() => service.listAllTools()).called(2);
    });
  });
}
