import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode options for the app.
enum AppThemeMode { light, dark, system }

/// App-wide user preferences backed by SharedPreferences.
///
/// Covers TTS voice/speed, auto-play TTS, auto-submit STT settings,
/// and theme mode (light/dark/system).
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

  // Defaults
  static const defaultVoice = 'af_heart';
  static const defaultSpeed = 1.0;
  static const defaultThemeMode = AppThemeMode.system;

  String _ttsVoice = defaultVoice;
  double _ttsSpeed = defaultSpeed;
  bool _autoPlayTts = false;
  bool _autoSubmitStt = false;
  AppThemeMode _themeMode = defaultThemeMode;
  bool _showMessageMetadata = false;
  bool _showSystemPrompt = false;
  bool _onboardingDismissed = false;
  bool _loaded = false;

  String get ttsVoice => _ttsVoice;
  double get ttsSpeed => _ttsSpeed;
  bool get autoPlayTts => _autoPlayTts;
  bool get autoSubmitStt => _autoSubmitStt;
  AppThemeMode get themeMode => _themeMode;
  bool get showMessageMetadata => _showMessageMetadata;
  bool get showSystemPrompt => _showSystemPrompt;
  bool get onboardingDismissed => _onboardingDismissed;
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
}
