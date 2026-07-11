// Web implementation of [MicroAppView]: an <iframe> embedded via the platform
// view registry. Only compiled on web (guarded by the conditional import in
// micro_app_view.dart), so dart:ui_web / package:web are safe here.
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget microAppPlatformView({
  required String url,
  required int reloadCounter,
}) => _WebIframe(url: url, reloadCounter: reloadCounter);

class _WebIframe extends StatefulWidget {
  final String url;
  final int reloadCounter;
  const _WebIframe({required this.url, required this.reloadCounter});

  @override
  State<_WebIframe> createState() => _WebIframeState();
}

class _WebIframeState extends State<_WebIframe> {
  late String _viewType;

  @override
  void initState() {
    super.initState();
    _register();
  }

  void _register() {
    // A unique view type per (url, reloadCounter) yields a fresh iframe, which
    // is the simplest reliable way to force a reload.
    _viewType =
        'microapp-iframe-${identityHashCode(this)}-${widget.reloadCounter}-'
        '${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      return web.HTMLIFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'clipboard-write';
    });
  }

  @override
  void didUpdateWidget(_WebIframe old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.reloadCounter != widget.reloadCounter) {
      setState(_register);
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
