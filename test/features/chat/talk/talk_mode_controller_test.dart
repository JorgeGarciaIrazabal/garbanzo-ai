import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_controller.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_recorder.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/voice_recording_helper.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatProvider extends Mock implements ChatProvider {}

class _MockSettingsProvider extends Mock implements SettingsProvider {}

class _FakeTalkRecorder extends TalkRecorder {
  int starts = 0;

  @override
  Future<void> start({required void Function(double db) onDb}) async {
    starts++;
  }

  @override
  void shutdown() {}
}

class _TranscriptTalkRecorder extends _FakeTalkRecorder {
  @override
  Future<VoiceRecordingResult?> stopAndTranscribe() async =>
      const VoiceRecordingResult(transcript: 'Hola');
}

void main() {
  group('TalkModeController.startCall', () {
    test('starts listening immediately and ignores a duplicate start', () async {
      final chat = _MockChatProvider();
      final settings = _MockSettingsProvider();
      final recorder = _FakeTalkRecorder();
      final streamingMessage = ValueNotifier<ChatMessage?>(null);
      when(() => chat.isSending).thenReturn(false);
      when(() => chat.streamingMessage).thenReturn(streamingMessage);
      final controller = TalkModeController(
        chat: chat,
        settings: settings,
        systemInstruction: 'Talk instruction',
        recorder: recorder,
      );

      await controller.startCall();
      await controller.startCall();

      expect(controller.isCallActive, isTrue);
      expect(controller.phase, TalkPhase.listening);
      expect(recorder.starts, 1);
      controller.dispose();
      streamingMessage.dispose();
    });

    test('sends the localized system instruction with the Talk turn', () async {
      final chat = _MockChatProvider();
      final settings = _MockSettingsProvider();
      final recorder = _TranscriptTalkRecorder();
      final streamingMessage = ValueNotifier<ChatMessage?>(null);
      when(() => chat.isSending).thenReturn(false);
      when(() => chat.streamingMessage).thenReturn(streamingMessage);
      when(() => settings.bargeInSensitivity).thenReturn(
        BargeInSensitivity.normal,
      );
      when(() => settings.ttsVoice).thenReturn(SettingsProvider.defaultVoice);
      when(() => settings.ttsSpeed).thenReturn(SettingsProvider.defaultSpeed);
      when(() => settings.autoLanguage).thenReturn(false);
      when(() => settings.preferredLanguages).thenReturn(const []);
      when(
        () => chat.sendMessage(
          any(),
          talkModeInstruction: any(named: 'talkModeInstruction'),
        ),
      ).thenAnswer((_) async {});
      final controller = TalkModeController(
        chat: chat,
        settings: settings,
        systemInstruction: 'Instrucción localizada',
        recorder: recorder,
      );

      await controller.startCall();
      await controller.onTap();

      verify(
        () => chat.sendMessage(
          'Hola',
          talkModeInstruction: 'Instrucción localizada',
        ),
      ).called(1);
      controller.dispose();
      streamingMessage.dispose();
    });
  });

  group('TalkModeController.bargeForSensitivity', () {
    test('off yields no detector', () {
      expect(
        TalkModeController.bargeForSensitivity(BargeInSensitivity.off),
        isNull,
      );
    });

    test('higher sensitivity means a lower bar and a shorter stretch', () {
      final low = TalkModeController.bargeForSensitivity(
        BargeInSensitivity.low,
      )!;
      final normal = TalkModeController.bargeForSensitivity(
        BargeInSensitivity.normal,
      )!;
      final high = TalkModeController.bargeForSensitivity(
        BargeInSensitivity.high,
      )!;
      expect(high.marginDb, lessThan(normal.marginDb));
      expect(normal.marginDb, lessThan(low.marginDb));
      expect(high.requiredLoud, lessThan(normal.requiredLoud));
      expect(normal.requiredLoud, lessThan(low.requiredLoud));
    });
  });

  group('TalkModeController.lastSentenceBoundary', () {
    test('returns the offset when no complete sentence yet', () {
      // No terminator+whitespace after the cursor.
      expect(TalkModeController.lastSentenceBoundary('Hello ther', 0), 0);
    });

    test('cuts just after the last completed sentence', () {
      const text = 'One. Two. Thr';
      final cut = TalkModeController.lastSentenceBoundary(text, 0);
      expect(text.substring(0, cut), 'One. Two.');
    });

    test('does not re-report sentences already spoken', () {
      const text = 'One. Two. Three.';
      // Already spoke up to just after "One."
      final cut = TalkModeController.lastSentenceBoundary(text, 4);
      expect(text.substring(4, cut).trim(), 'Two.');
    });

    test('handles ? and ! terminators', () {
      const text = 'Really? Yes! And';
      final cut = TalkModeController.lastSentenceBoundary(text, 0);
      expect(text.substring(0, cut), 'Really? Yes!');
    });

    test('a trailing sentence without following whitespace is not yet cut', () {
      // "Done." has no trailing space, so it is still considered in-progress
      // until more text (or the stream end) arrives.
      expect(TalkModeController.lastSentenceBoundary('Done.', 0), 0);
    });
  });

  group('TalkModeController.resolveReplyLanguage', () {
    test('manual override always wins', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: 'fr',
          autoLanguage: true,
          detected: 'es',
          preferred: const ['es'],
        ),
        'fr',
      );
      // Even with auto off and nothing detected.
      expect(
        TalkModeController.resolveReplyLanguage(
          override: 'it',
          autoLanguage: false,
          detected: null,
          preferred: const [],
        ),
        'it',
      );
    });

    test('auto mode follows the detected language', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: 'es',
          preferred: const [],
        ),
        'es',
      );
    });

    test('auto off keeps the pinned voice (null)', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: false,
          detected: 'es',
          preferred: const [],
        ),
        isNull,
      );
    });

    test('nothing detected yields null', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: null,
          preferred: const ['es'],
        ),
        isNull,
      );
    });

    test('a non-empty preferred list bounds auto switching', () {
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: 'fr',
          preferred: const ['en', 'es'],
        ),
        isNull,
      );
      expect(
        TalkModeController.resolveReplyLanguage(
          override: null,
          autoLanguage: true,
          detected: 'es',
          preferred: const ['en', 'es'],
        ),
        'es',
      );
    });
  });
}
