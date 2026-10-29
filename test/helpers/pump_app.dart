import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Builds a [MaterialApp] preconfigured with [AppLocalizations] delegates and
/// optional [providers] so widget tests do not repeat localization boilerplate.
Widget buildLocalizedTestApp(
  Widget child, {
  List<SingleChildWidget> providers = const [],
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  final app = MaterialApp(
    locale: locale,
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
  if (providers.isEmpty) return app;
  return MultiProvider(providers: providers, child: app);
}

/// Pumps [child] inside [buildLocalizedTestApp].
Future<void> pumpLocalizedApp(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget> providers = const [],
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    buildLocalizedTestApp(
      child,
      providers: providers,
      locale: locale,
      theme: theme,
    ),
  );
}
