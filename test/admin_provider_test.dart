// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/admin/models/admin_user.dart';
import 'package:garbanzo_ai/features/admin/models/mcp_server.dart';
import 'package:garbanzo_ai/features/admin/providers/admin_provider.dart';
import 'package:garbanzo_ai/features/admin/services/admin_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminService extends Mock implements AdminService {}

void main() {
  setUpAll(() {
    registerFallbackValue(McpTransport.http);
  });

  group('AdminProvider - users', () {
    late MockAdminService service;
    late AdminProvider provider;

    setUp(() {
      service = MockAdminService();
      provider = AdminProvider(service: service);
    });

    test('loadUsers populates users on success', () async {
      when(() => service.listUsers()).thenAnswer(
        (_) async => [
          const AdminUser(email: 'a@b.com', isAdmin: true),
          const AdminUser(email: 'c@d.com', isDisabled: true),
        ],
      );

      expect(provider.users, isEmpty);
      expect(provider.isLoadingUsers, isFalse);

      final future = provider.loadUsers();
      expect(provider.isLoadingUsers, isTrue);
      await future;

      expect(provider.isLoadingUsers, isFalse);
      expect(provider.users.length, 2);
      expect(provider.users.first.email, 'a@b.com');
      expect(provider.usersError, isNull);
    });

    test('loadUsers sets error on failure', () async {
      when(() => service.listUsers())
          .thenThrow(Exception('network down'));

      await provider.loadUsers();
      expect(provider.usersError, contains('network down'));
      expect(provider.users, isEmpty);
    });

    test('updateUser replaces existing entry', () async {
      when(() => service.listUsers()).thenAnswer(
        (_) async => [const AdminUser(email: 'a@b.com')],
      );
      when(
        () => service.updateUser('a@b.com', isAdmin: true, isDisabled: null),
      ).thenAnswer(
        (_) async => const AdminUser(email: 'a@b.com', isAdmin: true),
      );

      await provider.loadUsers();
      await provider.updateUser('a@b.com', isAdmin: true);

      expect(provider.users.single.isAdmin, isTrue);
    });
  });

  group('AdminProvider - mcp servers', () {
    late MockAdminService service;
    late AdminProvider provider;

    setUp(() {
      service = MockAdminService();
      provider = AdminProvider(service: service);
    });

    test('loadServers populates servers on success', () async {
      when(() => service.listMCPServers()).thenAnswer(
        (_) async => [
          const MCPServer(
            id: '1',
            name: 'Filesystem',
            transport: McpTransport.stdio,
            command: 'python',
          ),
        ],
      );

      await provider.loadServers();
      expect(provider.servers.length, 1);
      expect(provider.servers.first.name, 'Filesystem');
    });

    test('createServer appends created server', () async {
      when(() => service.listMCPServers()).thenAnswer((_) async => []);
      when(
        () => service.createMCPServer(
          name: any(named: 'name'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          transport: any(named: 'transport'),
          command: any(named: 'command'),
          args: any(named: 'args'),
          env: any(named: 'env'),
          authHeader: any(named: 'authHeader'),
          enabled: any(named: 'enabled'),
        ),
      ).thenAnswer(
        (_) async => const MCPServer(
          id: 'new',
          name: 'New',
          transport: McpTransport.http,
          url: 'http://x',
        ),
      );

      await provider.loadServers();
      final created = await provider.createServer(
        name: 'New',
        transport: McpTransport.http,
        url: 'http://x',
      );
      expect(created?.id, 'new');
      expect(provider.servers.length, 1);
    });

    test('deleteServer removes the server on success', () async {
      when(() => service.listMCPServers()).thenAnswer(
        (_) async => [
          const MCPServer(
            id: '1',
            name: 'One',
            transport: McpTransport.http,
            url: 'u',
          ),
        ],
      );
      when(() => service.deleteMCPServer('1'))
          .thenAnswer((_) async => Future.value());

      await provider.loadServers();
      expect(provider.servers.length, 1);
      final ok = await provider.deleteServer('1');
      expect(ok, isTrue);
      expect(provider.servers, isEmpty);
    });

    test('testServer returns a MCPTestResult even on failure', () async {
      when(() => service.testMCPServer('1'))
          .thenThrow(Exception('connection refused'));

      final result = await provider.testServer('1');
      expect(result, isNotNull);
      expect(result!.ok, isFalse);
    });
  });
}
