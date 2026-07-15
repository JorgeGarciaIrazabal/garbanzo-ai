import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_controller.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';

/// Full-screen, hands-free voice conversation surface (Talk Mode).
///
/// Reuses the caller's [ChatProvider] and [SettingsProvider] — passed in
/// explicitly because this page is pushed on the root navigator, above the
/// chat page's provider subtree. Owns the [TalkModeController] lifecycle.
class TalkModePage extends StatefulWidget {
  const TalkModePage({super.key, required this.chat, required this.settings});

  final ChatProvider chat;
  final SettingsProvider settings;

  /// Opens Talk Mode as a full-screen route, wiring the current providers in.
  static Future<void> open(
    BuildContext context, {
    required ChatProvider chat,
    required SettingsProvider settings,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TalkModePage(chat: chat, settings: settings),
      ),
    );
  }

  @override
  State<TalkModePage> createState() => _TalkModePageState();
}

class _TalkModePageState extends State<TalkModePage> {
  late final TalkModeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TalkModeController(
      chat: widget.chat,
      settings: widget.settings,
    );
    // Talk Mode owns TTS playback; suppress the chat's per-message auto-play so
    // replies aren't spoken twice (overlapping) while this call is open.
    widget.settings.talkModeActive = true;
    // Keep the screen awake for the duration of the call. Ignore failures on
    // platforms where the plugin isn't available.
    WakelockPlus.enable().ignore();
  }

  @override
  void dispose() {
    widget.settings.talkModeActive = false;
    WakelockPlus.disable().ignore();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            return Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    key: const ValueKey('talk_close_button'),
                    icon: const Icon(Icons.close),
                    tooltip: 'End call',
                    onPressed: () async {
                      await _controller.endCall();
                      if (context.mounted) {
                        await Navigator.of(context).maybePop();
                      }
                    },
                  ),
                ),
                const Spacer(),
                _TalkOrb(
                  phase: _controller.phase,
                  level: _controller.level,
                  onTap: _controller.onTap,
                ),
                const SizedBox(height: 40),
                Text(
                  _controller.statusText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _controller.phase == TalkPhase.error
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (_controller.isCallActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: IconButton.filledTonal(
                      key: const ValueKey('talk_mute_button'),
                      icon: Icon(
                        _controller.isMuted ? Icons.mic_off : Icons.mic,
                      ),
                      tooltip: _controller.isMuted ? 'Unmute' : 'Mute',
                      onPressed: _controller.toggleMute,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tappable central orb whose look reflects the current [TalkPhase]. While
/// listening it swells with the mic [level] for a live audio-reactive cue.
class _TalkOrb extends StatelessWidget {
  const _TalkOrb({
    required this.phase,
    required this.level,
    required this.onTap,
  });

  final TalkPhase phase;
  final double level;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (phase) {
      TalkPhase.idle => (scheme.primary, Icons.mic_none),
      TalkPhase.listening => (scheme.error, Icons.mic),
      TalkPhase.transcribing => (scheme.secondary, Icons.hourglass_top),
      TalkPhase.thinking => (scheme.tertiary, Icons.psychology_alt),
      TalkPhase.speaking => (scheme.primary, Icons.graphic_eq),
      TalkPhase.error => (scheme.error, Icons.refresh),
    };
    final busy = phase == TalkPhase.transcribing || phase == TalkPhase.thinking;
    // Listening: grow the orb up to +40px with the live mic level.
    final size = phase == TalkPhase.listening ? 180 + level * 40 : 180.0;

    return GestureDetector(
      key: const ValueKey('talk_orb'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color, width: 3),
        ),
        child: busy
            ? Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              )
            : Icon(icon, size: 72, color: color),
      ),
    );
  }
}
