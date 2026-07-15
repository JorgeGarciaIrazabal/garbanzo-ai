import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Manages a PipeWire `libpipewire-module-echo-cancel` instance on Linux so
/// Talk Mode can capture a microphone signal with the AI's own TTS playback
/// removed (WebRTC AEC) — the prerequisite for voice barge-in over speakers.
///
/// In **monitor mode** the module references the default sink's output (where
/// our TTS plays) as the far-end and exposes an echo-cancelled [sourceName]
/// node; capturing from that source instead of the raw mic yields ~30 dB of
/// echo reduction, so the AI's playback no longer self-triggers barge-in.
///
/// The module lives for as long as the owning `pw-cli -m` process runs, so we
/// keep that process alive and kill it on [dispose]. If a source with the same
/// name already exists (e.g. the user set one up), we reuse it and don't own it.
class PipewireEchoCancel {
  static const sourceName = 'garbanzo_aec_source';

  static const _moduleArgs =
      '{ monitor.mode = true '
      'source.props = { node.name = $sourceName '
      'node.description = "Garbanzo Echo-Cancelled Mic" } '
      'capture.props = { node.name = garbanzo_aec_capture } }';

  Process? _module;
  bool _owns = false;
  bool _disposed = false;

  /// Ensure the echo-cancel source exists. Returns `true` if it's available to
  /// capture from. Safe to call repeatedly (cheap once loaded). A no-op once
  /// [dispose] has been called, so a late call can't resurrect the module.
  Future<bool> ensureLoaded() async {
    if (_disposed) return false;
    if (_module != null) return true;
    if (kIsWeb || !Platform.isLinux) return false;
    if (!await _hasBinary('pw-cli') || !await _hasBinary('pw-record')) {
      return false;
    }
    if (_disposed) return false;
    if (await _sourceExists()) return true; // pre-existing — reuse, don't own

    final Process module;
    try {
      module = await Process.start('pw-cli', [
        '-m',
        'load-module',
        'libpipewire-module-echo-cancel',
        _moduleArgs,
      ]);
    } catch (e) {
      debugPrint('PipewireEchoCancel: load failed: $e');
      return false;
    }
    // Disposed while spawning — kill the just-started module and bail.
    if (_disposed) {
      module.kill();
      return false;
    }
    _module = module;
    _owns = true;

    // The node takes a moment to register; poll briefly for it.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_disposed) return false;
      if (await _sourceExists()) return true;
    }
    dispose();
    return false;
  }

  Future<bool> _sourceExists() async {
    try {
      final result = await Process.run('pw-cli', ['ls', 'Node']);
      return result.exitCode == 0 &&
          (result.stdout as String).contains(sourceName);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasBinary(String name) async {
    try {
      return (await Process.run('which', [name])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Unload the module (only if we loaded it) and release the process. Permanent
  /// — [ensureLoaded] won't reload afterwards.
  void dispose() {
    _disposed = true;
    if (_owns) _module?.kill();
    _module = null;
    _owns = false;
  }
}
