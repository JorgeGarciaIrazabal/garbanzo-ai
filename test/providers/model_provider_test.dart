import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/providers/model_provider.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:mocktail/mocktail.dart';

class MockChatService extends Mock implements ChatService {}

class MockAuthService extends Mock implements AuthService {}

ModelInfo _model(String id) =>
    ModelInfo(id: id, name: id, provider: 'ollama');

UserInfo _user({String? defaultModel}) =>
    UserInfo(email: 'test@example.com', defaultModel: defaultModel);

void main() {
  late MockChatService chat;
  late MockAuthService auth;

  setUp(() {
    chat = MockChatService();
    auth = MockAuthService();
    when(() => auth.cachedUser).thenReturn(_user());
  });

  ModelProvider provider() =>
      ModelProvider(chatService: chat, authService: auth);

  Future<ModelProvider> loaded() async {
    final p = provider();
    // _loadModels() runs from the constructor; let it settle.
    await Future<void>.delayed(Duration.zero);
    return p;
  }

  void stubModels(List<String> ids, {String? serverDefault}) {
    when(() => chat.listModels()).thenAnswer(
      (_) async => ModelList(
        models: ids.map(_model).toList(),
        defaultModel: serverDefault,
      ),
    );
  }

  group('default selection', () {
    test('prefers the user persisted default', () async {
      when(() => auth.cachedUser).thenReturn(_user(defaultModel: 'qwen3:8b'));
      stubModels(['llama3.2', 'qwen3:8b'], serverDefault: 'llama3.2');

      final p = await loaded();

      expect(p.availableModels.map((m) => m.id), ['llama3.2', 'qwen3:8b']);
      expect(p.selectedModelId, 'qwen3:8b');
    });

    test('falls back to the server default when no user default', () async {
      stubModels(['llama3.2', 'qwen3:8b'], serverDefault: 'qwen3:8b');

      final p = await loaded();

      expect(p.selectedModelId, 'qwen3:8b');
    });

    test('ignores a user default that is not in the list', () async {
      when(() => auth.cachedUser).thenReturn(_user(defaultModel: 'gone'));
      stubModels(['qwen3.8:27b', 'llama3.2'], serverDefault: 'gone');

      final p = await loaded();

      // Neither hint is valid → fallback chain picks qwen3.8 first.
      expect(p.selectedModelId, 'qwen3.8:27b');
    });

    test('fallback chain prefers qwen3.8 over qwen3 and llama3.2', () async {
      stubModels(['llama3.2', 'qwen3:8b', 'qwen3.8:27b']);

      final p = await loaded();

      expect(p.selectedModelId, 'qwen3.8:27b');
    });

    test('fallback lands on first model when no pattern matches', () async {
      stubModels(['mistral', 'phi3']);

      final p = await loaded();

      expect(p.selectedModelId, 'mistral');
    });
  });

  group('load failure', () {
    test('surfaces an error and leaves selection empty', () async {
      when(() => chat.listModels())
          .thenThrow(Exception('API Error (500): boom'));

      final p = await loaded();

      expect(p.availableModels, isEmpty);
      expect(p.selectedModelId, isNull);
      expect(p.error, isNotNull);
    });
  });

  group('selectModel', () {
    test('selects a known model and notifies', () async {
      stubModels(['llama3.2', 'qwen3:8b'], serverDefault: 'llama3.2');
      final p = await loaded();

      var notified = false;
      p.addListener(() => notified = true);
      p.selectModel('qwen3:8b');

      expect(p.selectedModelId, 'qwen3:8b');
      expect(notified, isTrue);
    });

    test('ignores an unknown model id', () async {
      stubModels(['llama3.2'], serverDefault: 'llama3.2');
      final p = await loaded();

      p.selectModel('does-not-exist');

      expect(p.selectedModelId, 'llama3.2');
    });
  });

  group('setDefaultModel', () {
    test('returns true when the profile update succeeds', () async {
      stubModels(['llama3.2'], serverDefault: 'llama3.2');
      when(() => auth.updateProfile(defaultModel: 'llama3.2'))
          .thenAnswer((_) async => AuthResult.success());
      final p = await loaded();

      expect(await p.setDefaultModel('llama3.2'), isTrue);
    });

    test('returns false when the profile update fails', () async {
      stubModels(['llama3.2'], serverDefault: 'llama3.2');
      when(() => auth.updateProfile(defaultModel: any(named: 'defaultModel')))
          .thenAnswer((_) async => AuthResult.failure('nope'));
      final p = await loaded();

      expect(await p.setDefaultModel('llama3.2'), isFalse);
    });
  });
}
