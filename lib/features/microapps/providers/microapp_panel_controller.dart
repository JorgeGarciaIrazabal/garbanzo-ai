import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/microapps/services/microapp_service.dart';

/// Drives the live micro-app panel shown beside the main chat.
///
/// It holds no business logic beyond turning a `micro_app` tool result (or a
/// manual open) into a display URL and a reload signal. The panel is a dumb
/// view of a dev-server URL; edits happen server-side (agent → files → HMR /
/// file-watcher), so opening/refreshing is all this needs to do. App-agnostic:
/// works for any registry app, with an optional data file (e.g. a house).
class MicroappPanelController extends ChangeNotifier {
  bool _open = false;
  String? _appPath; // e.g. "house-designer/"
  String? _appTitle; // human label for the header
  String? _file; // optional data file, e.g. "houses/tiny-cabin.house.json"
  String? _fileName; // base name of that file
  int? _devPort;
  bool _proxied = false; // load via the backend's /micro-apps proxy
  String? _panelToken; // ?mp_token= for the first proxied request
  int _reloadCounter = 0;

  bool get isOpen => _open;
  String? get file => _file;
  String? get fileName => _fileName;
  String? get appTitle => _appTitle;
  int? get devPort => _devPort;
  int get reloadCounter => _reloadCounter;

  /// The app URL reachable from THIS device. Proxied workspaces (deployments)
  /// load through the backend's /micro-apps reverse proxy on the API origin;
  /// otherwise composes `<api-host>:<devPort>` (phone-friendly) and falls
  /// back to loopback for same-host web/desktop.
  String? get url {
    if (_appPath == null) return null;
    final qsParts = <String>['embed=1'];
    if (_file != null) {
      qsParts
        ..add('project=/micro-apps/$_file')
        ..add('save=1');
    }
    if (_proxied) {
      if (_panelToken != null) qsParts.add('mp_token=$_panelToken');
      return '${MicroappService.proxyOrigin()}'
          '/micro-apps/$_appPath?${qsParts.join('&')}';
    }
    if (_devPort == null) return null;
    final base = Uri.parse(ApiClient.instance.baseUrl);
    final host = base.host;
    final scheme = base.scheme.isEmpty ? 'http' : base.scheme;
    final origin =
        (host.isNotEmpty && host != '127.0.0.1' && host != 'localhost')
        ? '$scheme://$host:$_devPort'
        : 'http://127.0.0.1:$_devPort';
    return '$origin/micro-apps/$_appPath?${qsParts.join('&')}';
  }

  /// Reveal (or refresh) the panel from a `micro_app` tool result.
  ///
  /// The result dict is produced by the backend `run_micro_app` and carries
  /// `{app, app_path, file?, file_name?, dev_port, proxied, panel_token?}`.
  /// Returns true if it was a recognizable micro-app signal.
  bool openFromToolResult(String? toolName, Object? result) {
    if (toolName != 'micro_app' || result is! Map) return false;
    final appPath = (result['app_path'] ?? result['app']) as String?;
    final port = (result['dev_port'] as num?)?.toInt();
    final proxied = result['proxied'] as bool? ?? false;
    if (appPath == null || (port == null && !proxied)) return false;
    _appPath = appPath.endsWith('/') ? appPath : '$appPath/';
    _appTitle = (result['app'] as String?) ?? _appPath;
    _file = result['file'] as String?;
    _fileName = result['file_name'] as String?;
    _devPort = port;
    _proxied = proxied;
    _panelToken = result['panel_token'] as String?;
    _open = true;
    _reloadCounter++; // an edit may have just landed — force a refresh
    notifyListeners();
    return true;
  }

  void reload() {
    _reloadCounter++;
    notifyListeners();
  }

  void close() {
    _open = false;
    notifyListeners();
  }

  /// True when a previously shown app can be brought back: closing the panel
  /// keeps the app/url state, only [isOpen] flips.
  bool get canReopen => !_open && url != null;

  /// Re-show the last app without needing to re-trigger the tool.
  void reopen() {
    if (url == null) return;
    _open = true;
    notifyListeners();
  }
}
