import 'package:flutter/material.dart';

/// Seed color for the app's [ColorScheme]s.
///
/// Still the stock Material 3 purple — replacing it with a garbanzo-brand
/// palette is tracked in IMPROVEMENTS-2026-07.md ("Give the app an identity").
const Color kSeedColor = Color(0xFF6750A4);

/// Builds the app theme for the given [brightness].
///
/// All shared component theming (app bar, cards, input borders) lives here so
/// light and dark stay in sync and pages don't re-style locally.
ThemeData buildTheme(Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: brightness,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}
