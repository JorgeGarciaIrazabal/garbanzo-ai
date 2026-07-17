import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI locale options. [system] follows the device locale, falling back to
/// English when the device locale isn't a supported language.
enum AppLocale { system, english, spanish }

/// Theme mode options for the app.
enum AppThemeMode { light, dark, system }

/// How easily talking over the AI interrupts it in Talk Mode.
/// [off] disables voice barge-in entirely (tap-to-interrupt still works).
enum BargeInSensitivity { off, low, normal, high }

/// App-wide user preferences backed by SharedPreferences.
///
/// Covers TTS voice/speed, auto-play TTS, auto-submit STT settings,
/// theme mode (light/dark/system), and spoken-language preferences
/// (preferredLanguages/autoLanguage — idea 13).
/// New settings sections can be added here as the app grows.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider() {
    _load();
  }

  static const _keyTtsVoice = 'settings_tts_voice';
  static const _keyTtsSpeed = 'settings_tts_speed';
  static const _keyAutoPlayTts = 'settings_auto_play_tts';
  static const _keyAutoSubmitStt = 'settings_auto_submit_stt';
  static const _keyThemeMode = 'settings_theme_mode';
  static const _keyShowMessageMetadata = 'settings_show_message_metadata';
  static const _keyShowSystemPrompt = 'settings_show_system_prompt';
  static const _keyOnboardingDismissed = 'settings_onboarding_dismissed';
  static const _keyPreferredLanguages = 'settings_preferred_languages';
  static const _keyAutoLanguage = 'settings_auto_language';
  static const _keyBargeInSensitivity = 'settings_barge_in_sensitivity';
  static const _keyLocale = 'settings_locale';

  // Defaults
  static const defaultVoice = 'af_heart';
  static const defaultSpeed = 1.0;
  static const defaultThemeMode = AppThemeMode.system;
  static const defaultAutoLanguage = true;
  static const defaultBargeInSensitivity = BargeInSensitivity.normal;

  String _ttsVoice = defaultVoice;
  double _ttsSpeed = defaultSpeed;
  bool _autoPlayTts = false;
  bool _autoSubmitStt = false;
  AppThemeMode _themeMode = defaultThemeMode;
  bool _showMessageMetadata = false;
  bool _showSystemPrompt = false;
  bool _onboardingDismissed = false;
  // Local-only, like ttsVoice/ttsSpeed above — no User column to sync
  // cross-device (idea 13.2): a spoken-language preference is cheap to
  // re-pick on a new device and doesn't need server-side persistence.
  List<String> _preferredLanguages = const [];
  bool _autoLanguage = defaultAutoLanguage;
  BargeInSensitivity _bargeInSensitivity = defaultBargeInSensitivity;
  AppLocale _appLocale = AppLocale.system;
  bool _loaded = false;

  /// True while the full-screen Talk Mode call is open. Transient (not
  /// persisted, doesn't notify). Talk Mode speaks replies itself
  /// sentence-by-sentence, so the per-message auto-play must stand down while
  /// this is set — otherwise the same reply plays twice, offset (see
  /// `SpeakButton` auto-play).
  bool talkModeActive = false;

  String get ttsVoice => _ttsVoice;
  double get ttsSpeed => _ttsSpeed;
  bool get autoPlayTts => _autoPlayTts;
  bool get autoSubmitStt => _autoSubmitStt;
  AppThemeMode get themeMode => _themeMode;
  bool get showMessageMetadata => _showMessageMetadata;
  bool get showSystemPrompt => _showSystemPrompt;
  bool get onboardingDismissed => _onboardingDismissed;
  List<String> get preferredLanguages => List.unmodifiable(_preferredLanguages);
  bool get autoLanguage => _autoLanguage;
  BargeInSensitivity get bargeInSensitivity => _bargeInSensitivity;
  AppLocale get appLocale => _appLocale;
  bool get loaded => _loaded;

  /// Converts AppThemeMode to Flutter's ThemeMode.
  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// Resolves to the Flutter [Locale] for [MaterialApp.locale], or null to
  /// let Flutter pick from the device locale.
  Locale? get flutterLocale {
    switch (_appLocale) {
      case AppLocale.english:
        return const Locale('en');
      case AppLocale.spanish:
        return const Locale('es');
      case AppLocale.system:
        return null;
    }
  }

  /// Resolves the effective BCP-47 primary language subtag for the chosen
  /// locale. Used to request locale-specific resources (e.g. built-in
  /// system-prompt templates) from the backend. Falls back to the device
  /// locale's language code when [appLocale] is [AppLocale.system].
  String get effectiveLanguageCode {
    switch (_appLocale) {
      case AppLocale.english:
        return 'en';
      case AppLocale.spanish:
        return 'es';
      case AppLocale.system:
        final device = PlatformDispatcher.instance.locale.languageCode;
        return device == 'es' ? 'es' : 'en';
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsVoice = prefs.getString(_keyTtsVoice) ?? defaultVoice;
    _ttsSpeed = prefs.getDouble(_keyTtsSpeed) ?? defaultSpeed;
    _autoPlayTts = prefs.getBool(_keyAutoPlayTts) ?? false;
    _autoSubmitStt = prefs.getBool(_keyAutoSubmitStt) ?? false;
    _themeMode = _parseThemeMode(prefs.getString(_keyThemeMode));
    _showMessageMetadata = prefs.getBool(_keyShowMessageMetadata) ?? false;
    _showSystemPrompt = prefs.getBool(_keyShowSystemPrompt) ?? false;
    _onboardingDismissed = prefs.getBool(_keyOnboardingDismissed) ?? false;
    _preferredLanguages =
        prefs.getStringList(_keyPreferredLanguages) ?? const [];
    _autoLanguage = prefs.getBool(_keyAutoLanguage) ?? defaultAutoLanguage;
    _bargeInSensitivity =
        BargeInSensitivity.values.asNameMap()[prefs.getString(
          _keyBargeInSensitivity,
        )] ??
        defaultBargeInSensitivity;
    _appLocale =
        AppLocale.values.asNameMap()[prefs.getString(_keyLocale)] ??
        AppLocale.system;
    _loaded = true;
    notifyListeners();
  }

  Future<void> dismissOnboarding() async {
    if (_onboardingDismissed) return;
    _onboardingDismissed = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDismissed, true);
  }

  AppThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      case 'system':
        return AppThemeMode.system;
      default:
        return defaultThemeMode;
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
  }

  Future<void> setTtsVoice(String voice) async {
    if (_ttsVoice == voice) return;
    _ttsVoice = voice;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTtsVoice, voice);
  }

  Future<void> setTtsSpeed(double speed) async {
    if (_ttsSpeed == speed) return;
    _ttsSpeed = speed.clamp(0.5, 2.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTtsSpeed, _ttsSpeed);
  }

  Future<void> setAutoPlayTts(bool value) async {
    if (_autoPlayTts == value) return;
    _autoPlayTts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoPlayTts, value);
  }

  Future<void> setAutoSubmitStt(bool value) async {
    if (_autoSubmitStt == value) return;
    _autoSubmitStt = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSubmitStt, value);
  }

  Future<void> setShowMessageMetadata(bool value) async {
    if (_showMessageMetadata == value) return;
    _showMessageMetadata = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowMessageMetadata, value);
  }

  Future<void> setShowSystemPrompt(bool value) async {
    if (_showSystemPrompt == value) return;
    _showSystemPrompt = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowSystemPrompt, value);
  }

  Future<void> setPreferredLanguages(List<String> languages) async {
    final normalized = List<String>.unmodifiable(languages);
    if (listEquals(_preferredLanguages, normalized)) return;
    _preferredLanguages = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyPreferredLanguages, normalized);
  }

  Future<void> setBargeInSensitivity(BargeInSensitivity value) async {
    if (_bargeInSensitivity == value) return;
    _bargeInSensitivity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBargeInSensitivity, value.name);
  }

  Future<void> setAutoLanguage(bool value) async {
    if (_autoLanguage == value) return;
    _autoLanguage = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoLanguage, value);
  }

  Future<void> setAppLocale(AppLocale value) async {
    if (_appLocale == value) return;
    _appLocale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, value.name);
  }
}
