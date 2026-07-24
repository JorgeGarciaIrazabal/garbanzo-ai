import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/talk/talk_mode_controller.dart';
import 'package:garbanzo_ai/features/settings/providers/settings_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Full-screen, hands-free voice conversation surface (Talk Mode).
///
/// Reuses the caller's [ChatProvider] and [SettingsProvider] — passed in
/// explicitly because this page is pushed on the root navigator, above the
/// chat page's provider subtree. Owns the [TalkModeController] lifecycle.
///
/// Layout is a call screen: the animated orb holds the floor (its motion says
/// who is talking), live captions show what was heard and what is being said,
/// and a call-style bottom bar carries mute + hang-up.
class TalkModePage extends StatefulWidget {
  const TalkModePage({
    super.key,
    required this.chat,
    required this.settings,
    required this.systemInstruction,
  });

  final ChatProvider chat;
  final SettingsProvider settings;
  final String systemInstruction;

  /// Opens Talk Mode as a full-screen route, wiring the current providers in.
  static Future<void> open(
    BuildContext context, {
    required ChatProvider chat,
    required SettingsProvider settings,
  }) {
    final systemInstruction = AppLocalizations.of(
      context,
    )!.talkModeSystemInstruction;
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TalkModePage(
          chat: chat,
          settings: settings,
          systemInstruction: systemInstruction,
        ),
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
      systemInstruction: widget.systemInstruction,
    );
    // Talk Mode owns TTS playback; suppress the chat's per-message auto-play so
    // replies aren't spoken twice (overlapping) while this call is open.
    widget.settings.talkModeActive = true;
    // Keep the screen awake for the duration of the call. Ignore failures on
    // platforms where the plugin isn't available.
    WakelockPlus.enable().ignore();
    // Wait until the route has painted before opening the mic (and potentially
    // showing the platform permission prompt). No extra tap is required.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.startCall());
    });
  }

  @override
  void dispose() {
    widget.settings.talkModeActive = false;
    WakelockPlus.disable().ignore();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _hangUp() async {
    await _controller.endCall();
    if (mounted) await Navigator.of(context).maybePop();
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
            final isError = _controller.phase == TalkPhase.error;
            return Column(
              children: [
                const Spacer(flex: 2),
                _TalkOrb(
                  phase: _controller.phase,
                  level: _controller.level,
                  onTap: _controller.onTap,
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _controller.statusText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isError ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isError) ...[
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.messageTapCircleToRetry,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                Expanded(
                  flex: 4,
                  child: _Captions(
                    userText: _controller.userTranscript,
                    assistantText: _controller.assistantText,
                  ),
                ),
                _ControlBar(
                  muted: _controller.isMuted,
                  languageOverride: _controller.languageOverride,
                  onToggleMute: _controller.toggleMute,
                  onLanguageSelected: _controller.setLanguageOverride,
                  onHangUp: _hangUp,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Live captions: the user's last transcript (so STT mistakes are visible at a
/// glance) above the assistant's streaming reply. Pinned to the bottom and
/// faded out at the top so a long reply scrolls away instead of piling up.
class _Captions extends StatelessWidget {
  const _Captions({required this.userText, required this.assistantText});

  final String userText;
  final String assistantText;

  @override
  Widget build(BuildContext context) {
    if (userText.isEmpty && assistantText.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
            stops: [0, 0.18],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          // reverse keeps the newest text in view as the reply streams in.
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (userText.isNotEmpty)
                  Text(
                    userText,
                    key: const ValueKey('talk_user_caption'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (userText.isNotEmpty && assistantText.isNotEmpty)
                  const SizedBox(height: 12),
                if (assistantText.isNotEmpty)
                  Text(
                    assistantText,
                    key: const ValueKey('talk_assistant_caption'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                      height: 1.45,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Call-style bottom bar: mute toggle + reply-language override + red hang-up.
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.muted,
    required this.languageOverride,
    required this.onToggleMute,
    required this.onLanguageSelected,
    required this.onHangUp,
  });

  final bool muted;

  /// Pinned reply language (ISO code), null when following the speech (Auto).
  final String? languageOverride;
  final Future<void> Function() onToggleMute;
  final void Function(String? code) onLanguageSelected;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            key: const ValueKey('talk_mute_button'),
            iconSize: 26,
            padding: const EdgeInsets.all(14),
            isSelected: muted,
            icon: const Icon(Icons.mic),
            selectedIcon: const Icon(Icons.mic_off),
            tooltip: muted ? 'Unmute' : 'Mute',
            onPressed: onToggleMute,
          ),
          const SizedBox(width: 28),
          // Reply-language override: Auto (follow the user's speech) or pin
          // one of the supported TTS languages for the rest of the call.
          PopupMenuButton<String>(
            key: const ValueKey('talk_language_button'),
            tooltip: languageOverride == null
                ? 'Reply language: Auto'
                : 'Reply language: '
                      '${TalkModeController.supportedLanguages[languageOverride] ?? languageOverride}',
            initialValue: languageOverride ?? 'auto',
            onSelected: (code) =>
                onLanguageSelected(code == 'auto' ? null : code),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'auto',
                child: Text(AppLocalizations.of(context)!.messageAuto),
              ),
              const PopupMenuDivider(),
              for (final entry in TalkModeController.supportedLanguages.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            child: IgnorePointer(
              // The menu button handles taps; the tonal button is just the look.
              child: IconButton.filledTonal(
                iconSize: 26,
                padding: const EdgeInsets.all(14),
                isSelected: languageOverride != null,
                icon: const Icon(Icons.translate),
                onPressed: () {},
              ),
            ),
          ),
          const SizedBox(width: 28),
          IconButton(
            key: const ValueKey('talk_close_button'),
            iconSize: 30,
            padding: const EdgeInsets.all(16),
            style: IconButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            icon: const Icon(Icons.call_end),
            tooltip: AppLocalizations.of(context)!.messageEndCall,
            onPressed: onHangUp,
          ),
        ],
      ),
    );
  }
}

/// Tappable central orb — the page's one animated element. Its motion encodes
/// the phase: a slow breath while idle, a mic-level halo while listening,
/// outward ripples while speaking (sound leaving the device), and a rotating
/// arc while transcribing/thinking. Honors the platform reduced-motion
/// setting by rendering statically.
class _TalkOrb extends StatefulWidget {
  const _TalkOrb({
    required this.phase,
    required this.level,
    required this.onTap,
  });

  final TalkPhase phase;
  final double level;
  final Future<void> Function() onTap;

  @override
  State<_TalkOrb> createState() => _TalkOrbState();
}

class _TalkOrbState extends State<_TalkOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// Mic level smoothed per frame so the listening halo glides instead of
  /// jumping at the 100 ms sample rate.
  double _smoothedLevel = 0;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      _smoothedLevel += (widget.level - _smoothedLevel) * 0.15;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _anim.stop();
    } else if (!_anim.isAnimating) {
      _anim.repeat();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (widget.phase) {
      TalkPhase.idle => (scheme.primary, Icons.mic_none),
      TalkPhase.listening => (scheme.error, Icons.mic),
      TalkPhase.transcribing => (scheme.secondary, Icons.hourglass_top),
      TalkPhase.thinking => (scheme.tertiary, Icons.psychology_alt),
      TalkPhase.speaking => (scheme.primary, Icons.graphic_eq),
      TalkPhase.error => (scheme.error, Icons.refresh),
    };

    return GestureDetector(
      key: const ValueKey('talk_orb'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => CustomPaint(
          size: const Size.square(236),
          painter: _OrbPainter(
            t: _anim.value,
            level: _smoothedLevel,
            phase: widget.phase,
            color: color,
          ),
          child: child,
        ),
        child: SizedBox.square(
          dimension: 236,
          child: Center(child: Icon(icon, size: 64, color: color)),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.level,
    required this.phase,
    required this.color,
  });

  /// Animation progress, 0..1 looping (frozen when reduced motion is on).
  final double t;
  final double level;
  final TalkPhase phase;
  final Color color;

  static const _baseRadius = 78.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    var radius = _baseRadius;
    if (phase == TalkPhase.idle) {
      radius += 2.5 * math.sin(t * 2 * math.pi); // slow breath
    }

    // Body: soft radial fill + crisp outline.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );

    switch (phase) {
      case TalkPhase.listening:
        // Halo that swells with the mic level.
        canvas.drawCircle(
          center,
          radius + 8 + level * 30,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color.withValues(alpha: 0.45 + level * 0.35),
        );
      case TalkPhase.speaking:
        // Two staggered ripples travelling outward.
        for (var k = 0; k < 2; k++) {
          final p = (t + k / 2) % 1;
          canvas.drawCircle(
            center,
            radius + 6 + p * 42,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = color.withValues(alpha: (1 - p) * 0.4),
          );
        }
      case TalkPhase.transcribing:
      case TalkPhase.thinking:
        // Two opposed arcs orbiting the rim.
        final rect = Rect.fromCircle(center: center, radius: radius + 10);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.7);
        final start = t * 2 * math.pi;
        canvas.drawArc(rect, start, 1.3, false, paint);
        canvas.drawArc(rect, start + math.pi, 1.3, false, paint);
      case TalkPhase.idle:
      case TalkPhase.error:
        break;
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.level != level ||
      old.phase != phase ||
      old.color != color;
}
