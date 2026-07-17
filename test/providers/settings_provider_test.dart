import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helpers to wait for the async _load() call in the constructor to finish.
Future<SettingsProvider> _makeLoaded() async {
  final provider = SettingsProvider();
  while (!provider.loaded) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsProvider defaults', () {
    test('exposes sensible defaults before any write', () async {
      final p = await _makeLoaded();
      expect(p.ttsVoice, SettingsProvider.defaultVoice);
      expect(p.ttsSpeed, SettingsProvider.defaultSpeed);
      expect(p.autoPlayTts, isFalse);
      expect(p.autoSubmitStt, isFalse);
      expect(p.themeMode, SettingsProvider.defaultThemeMode);
      expect(p.showMessageMetadata, isFalse);
      expect(p.showSystemPrompt, isFalse);
      expect(p.preferredLanguages, isEmpty);
      expect(p.autoLanguage, isTrue);
      expect(p.loaded, isTrue);
    });

    test('maps AppThemeMode to Flutter ThemeMode', () async {
      final p = await _makeLoaded();
      await p.setThemeMode(AppThemeMode.light);
      expect(p.flutterThemeMode, ThemeMode.light);
      await p.setThemeMode(AppThemeMode.dark);
      expect(p.flutterThemeMode, ThemeMode.dark);
      await p.setThemeMode(AppThemeMode.system);
      expect(p.flutterThemeMode, ThemeMode.system);
    });
  });

  group('SettingsProvider persistence', () {
    test('loads stored values on init', () async {
      SharedPreferences.setMockInitialValues({
        'settings_tts_voice': 'af_bella',
        'settings_tts_speed': 1.4,
        'settings_auto_play_tts': true,
        'settings_auto_submit_stt': true,
        'settings_theme_mode': 'dark',
        'settings_show_message_metadata': true,
        'settings_show_system_prompt': true,
        'settings_preferred_languages': ['en', 'es'],
        'settings_auto_language': false,
      });
      final p = await _makeLoaded();
      expect(p.ttsVoice, 'af_bella');
      expect(p.ttsSpeed, 1.4);
      expect(p.autoPlayTts, isTrue);
      expect(p.autoSubmitStt, isTrue);
      expect(p.themeMode, AppThemeMode.dark);
      expect(p.showMessageMetadata, isTrue);
      expect(p.showSystemPrompt, isTrue);
      expect(p.preferredLanguages, ['en', 'es']);
      expect(p.autoLanguage, isFalse);
    });

    test('unknown theme mode string falls back to default', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode': 'neon-green',
      });
      final p = await _makeLoaded();
      expect(p.themeMode, SettingsProvider.defaultThemeMode);
    });
  });

  group('SettingsProvider setters', () {
    test('setTtsSpeed clamps to [0.5, 2.0]', () async {
      final p = await _makeLoaded();
      await p.setTtsSpeed(0.1);
      expect(p.ttsSpeed, 0.5);
      await p.setTtsSpeed(5.0);
      expect(p.ttsSpeed, 2.0);
      await p.setTtsSpeed(1.25);
      expect(p.ttsSpeed, 1.25);
    });

    test('setters notify listeners only when value changes', () async {
      final p = await _makeLoaded();
      var notifications = 0;
      p.addListener(() => notifications++);

      await p.setAutoPlayTts(false); // same as default
      expect(notifications, 0);

      await p.setAutoPlayTts(true);
      expect(notifications, 1);

      await p.setAutoPlayTts(true); // unchanged
      expect(notifications, 1);
    });

    test('setThemeMode persists the choice', () async {
      final p = await _makeLoaded();
      await p.setThemeMode(AppThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_theme_mode'), 'dark');
    });

    test('setTtsVoice persists the choice', () async {
      final p = await _makeLoaded();
      await p.setTtsVoice('af_bella');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_tts_voice'), 'af_bella');
    });

    test('setPreferredLanguages persists and notifies once per real change',
        () async {
      final p = await _makeLoaded();
      var notifications = 0;
      p.addListener(() => notifications++);

      await p.setPreferredLanguages(const []); // same as default
      expect(notifications, 0);

      await p.setPreferredLanguages(['en', 'es']);
      expect(notifications, 1);
      expect(p.preferredLanguages, ['en', 'es']);

      await p.setPreferredLanguages(['en', 'es']); // unchanged (order+content)
      expect(notifications, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('settings_preferred_languages'), ['en', 'es']);
    });

    test('setAutoLanguage persists the choice', () async {
      final p = await _makeLoaded();
      await p.setAutoLanguage(false);
      expect(p.autoLanguage, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_auto_language'), isFalse);
    });
  });
}
