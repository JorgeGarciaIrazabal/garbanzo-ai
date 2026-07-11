import 'package:flutter/widgets.dart';

// Platform-specific implementation, selected at compile time:
//   - web  → an <iframe> via dart:ui_web + package:web
//   - native (Android/iOS) → webview_flutter
//   - desktop → an "open in browser" fallback
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_view_native.dart'
    if (dart.library.js_interop) 'package:garbanzo_ai/features/microapps/widgets/micro_app_view_web.dart'
    as impl;

/// Displays a micro-app URL. This is a DUMB view — it only renders the page.
/// The agent edits files server-side and the app self-reloads via HMR / its
/// own file watcher, so no JS bridge lives here.
///
/// Bump [reloadCounter] to force a reload (e.g. after an agent turn completes).
class MicroAppView extends StatelessWidget {
  final String url;
  final int reloadCounter;

  const MicroAppView({super.key, required this.url, this.reloadCounter = 0});

  @override
  Widget build(BuildContext context) =>
      impl.microAppPlatformView(url: url, reloadCounter: reloadCounter);
}
