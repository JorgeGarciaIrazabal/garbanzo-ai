import 'package:flutter/widgets.dart';

/// Encapsulates the chat page's "smart" auto-scroll behaviour so it can be
/// shared across message-list screens (1:1 chat and multi-agent rooms).
///
/// The rules, ported from the June chat-page polish:
///   • Follow live streaming growth ONLY when the user is already reading the
///     latest content — never yank them out of scrollback.
///   • Jump (don't animate) on container switches (e.g. opening another room).
///   • Animate a gentle scroll when new whole messages arrive and the user is
///     near the bottom (or just sent one).
///   • Expose a [showJumpToBottom] flag so the page can render a
///     "jump to latest" pill while the user is scrolled up.
///
/// The helper owns its [ScrollController]; the widget wires [attach] in
/// `initState` and [dispose] in its own `dispose`.
class SmartScrollController {
  SmartScrollController({this.nearBottomThreshold = 150});

  /// How close (in pixels) to the bottom counts as "near the bottom" and thus
  /// still following the conversation.
  final double nearBottomThreshold;

  final ScrollController controller = ScrollController();

  /// True while the user has scrolled up, away from the newest content.
  final ValueNotifier<bool> showJumpToBottom = ValueNotifier(false);

  int _lastItemCount = 0;
  String? _lastContainerId;

  /// Start listening to scroll offset changes. Call once from `initState`.
  void attach() => controller.addListener(_onScroll);

  bool get isNearBottom {
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.maxScrollExtent - position.pixels <= nearBottomThreshold;
  }

  void _onScroll() {
    final show = !isNearBottom;
    if (show != showJumpToBottom.value) showJumpToBottom.value = show;
  }

  /// Follow the growing streaming bubble. Jumps instead of animating: at ~12
  /// content updates/second, overlapping animations would thrash.
  void followStreaming() {
    if (!isNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToBottom(animate: false);
    });
  }

  /// Handle structural list changes: jump to bottom on a container switch;
  /// otherwise follow newly-added items when the user forced it (they just
  /// sent a message) or is already near the bottom.
  void handleStructural({
    required int itemCount,
    required String? containerId,
    bool forceFollow = false,
  }) {
    if (containerId != _lastContainerId) {
      _lastContainerId = containerId;
      _lastItemCount = itemCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom(animate: false);
      });
      return;
    }

    if (itemCount != _lastItemCount) {
      final shouldScroll = forceFollow || isNearBottom;
      _lastItemCount = itemCount;
      if (shouldScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToBottom();
        });
      }
    }
  }

  double _lastBottomInset = 0;
  bool _keyboardFollowsBottom = false;

  /// Keyboard-aware follow: when the on-screen keyboard opens the viewport
  /// shrinks, hiding the newest messages unless the list stays pinned to the
  /// bottom. Call from `didChangeMetrics` with the view's bottom inset. Only
  /// follows when the user was already near the bottom when the keyboard
  /// started opening — never yanks them out of scrollback.
  void handleKeyboardInset(double bottomInset) {
    if (bottomInset > _lastBottomInset) {
      if (_lastBottomInset == 0) _keyboardFollowsBottom = isNearBottom;
      if (_keyboardFollowsBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToBottom(animate: false);
        });
      }
    }
    _lastBottomInset = bottomInset;
  }

  void scrollToBottom({bool animate = true}) {
    if (!controller.hasClients) return;
    final target = controller.position.maxScrollExtent;
    if (animate) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  void dispose() {
    controller.removeListener(_onScroll);
    controller.dispose();
    showJumpToBottom.dispose();
  }
}
