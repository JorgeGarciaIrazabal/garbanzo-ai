// Native implementation of [MicroAppView]. Compiled on every non-web platform:
//   - Android/iOS → a `webview_flutter` WebView
//   - Windows    → a `flutter_inappwebview` WebView2 (real embedded panel)
//   - Linux/macOS → "open in browser" fallback (`flutter_inappwebview` has no
//     stable Linux backend; see the comment in micro_app_view_windows.dart).
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:garbanzo_ai/features/microapps/widgets/micro_app_view_windows.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget microAppPlatformView({required String url, required int reloadCounter}) {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return _WebViewHost(url: url, reloadCounter: reloadCounter);
  }
  // Windows is the only desktop OS we deploy to; render the live app inline
  // there. Linux is the developer's host and gets the browser link (a stable
  // inline webview plugin for Linux doesn't exist — see the pub.dev survey;
  // `desktop_webview_window` was considered but its window-overlay model is
  // a much larger integration cost).
  if (Platform.isWindows) {
    return microAppWindowsInAppWebView(url: url, reloadCounter: reloadCounter);
  }
  return _OpenInBrowserCard(url: url);
}

class _WebViewHost extends StatefulWidget {
  final String url;
  final int reloadCounter;
  const _WebViewHost({required this.url, required this.reloadCounter});

  @override
  State<_WebViewHost> createState() => _WebViewHostState();
}

class _WebViewHostState extends State<_WebViewHost> {
  late final WebViewController _controller;

  /// Load state so the panel can swap a failed preview for a retry card
  /// instead of silently showing a blank WebView (which was the symptom in
  /// "Micro-apps integration not working on Android" — a blocked HTTP load
  /// or a 404 left the panel blank with no clue). Null = unknown/loading.
  ///
  /// True on success, False on HTTP error (e.g. 404 "not found") or
  /// a top-frame resource error; subsequent navigations flip it back to
  /// unknown and then success/error as they resolve. Null is also reset on
  /// didUpdateWidget so a new URL/reload starts fresh.
  bool? _loadOk;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loadOk = null);
          },
          onPageFinished: (_) {
            // A page that loaded (even an error page that came back over the
            // wire) is "not known-bad" until onHttpError/onWebResourceError
            // says otherwise. We keep the optimistic-but-observable model:
            // onHttpError is authoritative for the top frame's HTTP status,
            // and onWebResourceError covers the cleartext-blocked /
            // connection-refused cases where no HTTP response arrives at all.
            if (mounted && _loadOk == null) setState(() => _loadOk = true);
          },
          onHttpError: (error) {
            // WebView considers 404 as a successful page load with a response.
            // Only the top frame determines "the app didn't load": a 404 from
            // a sub-resource (asset) shouldn't replace the panel with the
            // retry card. The dev-server's 404 body ("not found") is what the
            // user saw for the stale-worktree bug, so surfacing it here turns
            // the silent blank into an actionable card with a Retry. We
            // approximate "top frame" by comparing the failing request URI
            // to the URL the controller was asked to load.
            final reqUri = error.request?.uri;
            final statusCode = error.response?.statusCode ?? 0;
            final isMainFrame =
                reqUri == null || reqUri.toString() == widget.url;
            if (isMainFrame && statusCode >= 400 && mounted) {
              setState(() => _loadOk = false);
            }
          },
          onWebResourceError: (err) {
            // Cleartext-blocked, connection refused, DNS failure, etc.
            // isForMainFrame is null on iOS; treat null as "maybe main" so a
            // connection failure still surfaces instead of staying blank.
            final main = err.isForMainFrame;
            if ((main == null || main) && mounted) {
              setState(() => _loadOk = false);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didUpdateWidget(_WebViewHost old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      setState(() => _loadOk = null);
      _controller.loadRequest(Uri.parse(widget.url));
    } else if (old.reloadCounter != widget.reloadCounter) {
      setState(() => _loadOk = null);
      _controller.reload();
    }
  }

  void _retry() {
    setState(() => _loadOk = null);
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    // While loading, show a placeholder Spinner so the panel isn't blank
    // during the few-hundred-ms first-paint window (or the long dev-server
    // start). On failure, swap to a retry card.
    if (_loadOk == false) return _LoadFailedCard(onRetry: _retry);
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loadOk == null)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }
}

/// Fallback shown when the top-frame micro-app failed to load. Lets the user
/// retry (the agent may have just published, the workspace may have just
/// finished starting, or the worktree may have just synced a new app in) and
/// surfaces the URL for debugging, mirroring the desktop "open in browser"
/// card's affordances.
class _LoadFailedCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadFailedCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              l10n.titleMicroAppLoadFailed,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.messageMicroAppLoadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.labelRetry),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenInBrowserCard extends StatelessWidget {
  final String url;
  const _OpenInBrowserCard({required this.url});

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_browser,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Preview opens in a browser on this platform',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The live app runs in your system browser. Agent edits still '
              'apply live to the shared workspace; reload the browser tab to '
              'see them.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SelectableText(url, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                  onPressed: _open,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(AppLocalizations.of(context)!.labelCopyUrl),
                  onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
