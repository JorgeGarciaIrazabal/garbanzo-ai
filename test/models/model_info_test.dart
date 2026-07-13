import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';

void main() {
  group('ModelInfo', () {
    test('fromJson parses all fields', () {
      final info = ModelInfo.fromJson({
        'id': 'llama3.2',
        'name': 'Llama 3.2',
        'description': 'A great model',
        'context_length': 4096,
        'provider': 'ollama',
      });
      expect(info.id, 'llama3.2');
      expect(info.name, 'Llama 3.2');
      expect(info.description, 'A great model');
      expect(info.contextLength, 4096);
      expect(info.provider, 'ollama');
    });

  });

  group('ModelList', () {
    test('fromJson parses model list', () {
      final list = ModelList.fromJson({
        'models': [
          {
            'id': 'model-1',
            'name': 'Model 1',
            'provider': 'ollama',
          },
          {
            'id': 'model-2',
            'name': 'Model 2',
            'provider': 'ollama',
          },
        ],
      });
      expect(list.models.length, 2);
      expect(list.models[0].id, 'model-1');
      expect(list.models[1].id, 'model-2');
    });
  });
}
