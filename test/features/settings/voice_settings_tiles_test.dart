import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/chat/services/audio_service.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/features/settings/widgets/drawer_sections/app_settings_section.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VoiceSettingsTiles.uniqueLanguages', () {
    const voices = [
      VoiceOption(id: 'af_heart', name: 'Heart', language: 'English', langCode: 'en'),
      VoiceOption(id: 'am_adam', name: 'Adam', language: 'English', langCode: 'en'),
      VoiceOption(id: 'ef_dora', name: 'Dora', language: 'Spanish', langCode: 'es'),
      VoiceOption(id: 'ff_siwis', name: 'Siwis', language: 'French', langCode: 'fr'),
    ];

    test('dedupes by lang code, keeping catalog order', () {
      final langs = VoiceSettingsTiles.uniqueLanguages(voices);
      expect(langs.map((l) => l.code), ['en', 'es', 'fr']);
      expect(langs.map((l) => l.name), ['English', 'Spanish', 'French']);
    });

    test('empty catalog yields no languages', () {
      expect(VoiceSettingsTiles.uniqueLanguages(const []), isEmpty);
    });
  });

  group('VoiceSettingsTiles language settings', () {
    const voices = [
      VoiceOption(id: 'af_heart', name: 'Heart', language: 'English', langCode: 'en'),
      VoiceOption(id: 'ef_dora', name: 'Dora', language: 'Spanish', langCode: 'es'),
    ];

    Future<SettingsProvider> pump(WidgetTester tester) async {
      final settings = SettingsProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
              body: SingleChildScrollView(
                child: VoiceSettingsTiles(loadVoices: () async => voices),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return settings;
    }

    testWidgets('auto toggle renders on by default and toggles off, hiding '
        'the language chips', (tester) async {
      final settings = await pump(tester);
      final toggle = find.byKey(const ValueKey('auto_language_switch'));
      expect(toggle, findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(find.byKey(const ValueKey('language_chip_en')), findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();
      expect(settings.autoLanguage, isFalse);
      expect(find.byKey(const ValueKey('language_chip_en')), findsNothing);
    });

    testWidgets('tapping chips selects and deselects preferred languages', (
      tester,
    ) async {
      final settings = await pump(tester);
      final spanish = find.byKey(const ValueKey('language_chip_es'));
      expect(spanish, findsOneWidget);

      await tester.tap(spanish);
      await tester.pump();
      expect(settings.preferredLanguages, ['es']);

      await tester.tap(find.byKey(const ValueKey('language_chip_en')));
      await tester.pump();
      expect(settings.preferredLanguages, ['es', 'en']);

      await tester.tap(spanish);
      await tester.pump();
      expect(settings.preferredLanguages, ['en']);
    });
  });
}
