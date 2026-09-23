import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/services/read_aloud_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native audio and preview URLs use API origin and bearer header', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient.instance;
    await api.loadToken();
    await api.setToken('read-aloud-test-token');
    final service = ReadAloudService(api: api);

    final audio = await service.audioRequest('session-1', startSegment: 3);
    expect(audio.uri.origin, Uri.parse(api.baseUrl).origin);
    expect(audio.uri.path, '/api/v1/tts/read-aloud/sessions/session-1/audio');
    expect(audio.uri.queryParameters['start_segment'], '3');
    expect(audio.headers['Authorization'], 'Bearer read-aloud-test-token');

    final preview = await service.previewRequest('alba');
    expect(preview.uri.origin, Uri.parse(api.baseUrl).origin);
    expect(preview.uri.path, '/api/v1/tts/read-aloud/voices/alba/preview');
    expect(preview.headers['Authorization'], 'Bearer read-aloud-test-token');
    await api.setToken(null);
  });
}
