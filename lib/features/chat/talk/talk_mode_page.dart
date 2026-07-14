import 'package:flutter/material.dart';

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
  }

  @override
  void dispose() {
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
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const Spacer(),
                _TalkOrb(phase: _controller.phase, onTap: _controller.onTap),
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
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tappable central orb whose look reflects the current [TalkPhase].
class _TalkOrb extends StatelessWidget {
  const _TalkOrb({required this.phase, required this.onTap});

  final TalkPhase phase;
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

    return GestureDetector(
      key: const ValueKey('talk_orb'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 180,
        height: 180,
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
