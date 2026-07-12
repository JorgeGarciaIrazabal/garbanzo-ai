import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

/// Seed color for the app's [ColorScheme]s.
///
/// Sampled from the app icon's garbanzo bean (assets/app_icon_1024.png):
/// an electric royal blue, with M3 deriving the violet/periwinkle harmonies
/// that echo the icon's rings.
const Color kSeedColor = Color(0xFF2652BF);

/// Builds the app theme for the given [brightness].
///
/// All shared component theming (app bar, cards, input borders) lives here so
/// light and dark stay in sync and pages don't re-style locally.
///
/// Typography: Outfit for display/headline/title (matches the icon's
/// geometric feel), Inter for body/label. Fonts come from google_fonts and
/// gracefully fall back to the platform default when offline.
ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: brightness,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    // One consistent route transition everywhere (desktop/web default to
    // none/zoom otherwise): a shared-axis style fade-forward.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  final inter = GoogleFonts.interTextTheme(base.textTheme);
  TextStyle? outfit(TextStyle? style) =>
      style == null ? null : GoogleFonts.outfit(textStyle: style);

  return base.copyWith(
    textTheme: inter.copyWith(
      displayLarge: outfit(inter.displayLarge),
      displayMedium: outfit(inter.displayMedium),
      displaySmall: outfit(inter.displaySmall),
      headlineLarge: outfit(inter.headlineLarge),
      headlineMedium: outfit(inter.headlineMedium),
      headlineSmall: outfit(inter.headlineSmall),
      titleLarge: outfit(inter.titleLarge),
    ),
  );
}
