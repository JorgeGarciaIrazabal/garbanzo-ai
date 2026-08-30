import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Encapsulates the chat page's "smart" auto-scroll behaviour so it can be
/// shared across message-list screens (1:1 chat and multi-agent rooms).
///
/// The rules:
///   • While an answer streams in and the user is reading the latest content,
///     the view pins the answer's TOP to the viewport top and holds it there —
///     no chasing of the growing text. The pin target is constant, so the
///     reader's position never changes while the answer streams (and tool
///     messages inserted above the answer are absorbed by the same pin).
///     A user who scrolls away is never dragged back.
///   • The jump-to-bottom pill rides the tail of a live stream when tapped
///     (opt-in bottom-chase until the user scrolls away or the stream ends).
///   • Jump (don't animate) on container switches (e.g. opening another room).
///   • Animate a gentle scroll when new whole messages arrive and the user is
///     near the bottom (or just sent one).
///   • Expose a [showJumpToBottom] flag so the page can render a
///     "jump to latest" pill while the user is scrolled up.
///
/// The helper owns its [ScrollController]; the widget wires [attach] in
/// `initState` and [dispose] in its own `dispose`. Anchoring to the streaming
/// bubble requires the page to wrap that bubble with [streamAnchorKey].
class SmartScrollController {
  SmartScrollController({this.nearBottomThreshold = 150});

  /// How close (in pixels) to the bottom counts as "near the bottom" and thus
  /// still following the conversation.
  final double nearBottomThreshold;

  final ScrollController controller = ScrollController();

  /// Key of the streaming bubble, used to locate the answer inside the
  /// viewport. The page re-wraps whichever bubble is streaming with it.
  final GlobalKey streamAnchorKey = GlobalKey();

  /// True while the user has scrolled up, away from the newest content.
  final ValueNotifier<bool> showJumpToBottom = ValueNotifier(false);

  String? _streamId;

  /// Armed at the first tick of a stream when the user is near the bottom;
  /// disarmed for good once the user takes over (a settled scroll offset
  /// away from our last programmatic placement) or the stream ends.
  bool _armed = false;

  /// True while the user is riding the tail of a live stream (they tapped
  /// the jump pill). This is the only bottom-chase in the helper, and it is
  /// strictly opt-in.
  bool _riding = false;

  /// Offset the helper last placed the view at. A tick finding a settled
  /// position far from it means the user scrolled on their own — release
  /// the stream.
  double _lastProgrammaticOffset = 0;

  /// How far from our last programmatic offset a settled scroll position
  /// may drift before it counts as the user taking over. Content growth
  /// never moves the offset, so any settled deviation is a user scroll.
  static const _userTakeoverEpsilon = 2.0;

  int _lastItemCount = 0;
  String? _lastContainerId;

  bool get _streamingNow => _streamId != null;

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

  /// One streaming-channel update; `null` means the stream just ended.
  void handleStreamingTick(String? messageId) {
    final id = (messageId != null && messageId.isNotEmpty) ? messageId : null;
    if (id == null) {
      _streamId = null;
      _armed = false;
      _riding = false;
      return;
    }
    if (id != _streamId) {
      // A new answer took over the channel: (re)arm the pin, but only when
      // the user is reading the latest content — never yank scrollback.
      _streamId = id;
      _riding = false;
      _armed = isNearBottom;
      _lastProgrammaticOffset = controller.hasClients
          ? controller.position.pixels
          : 0;
    }
    if (_riding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rideTail());
    } else if (_armed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pinAnswerTop());
    }
  }

  /// Jump-to-bottom action. While a stream is still live this rides its tail
  /// — the user explicitly asked to follow the latest content — which also
  /// cancels the answer-top pin.
  void resumeFollow() {
    if (!_streamingNow) {
      scrollToBottom();
      return;
    }
    _armed = false;
    _riding = true;
    scrollToBottom(animate: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _rideTail());
  }

  /// Keep the newest content pinned to the viewport bottom while riding,
  /// until the user scrolls away or the stream ends.
  void _rideTail() {
    if (!_riding || !_streamingNow || !controller.hasClients) {
      _riding = false;
      return;
    }
    final position = controller.position;
    if (!position.hasContentDimensions) {
      return;
    }
    if ((position.pixels - _lastProgrammaticOffset).abs() >
        _userTakeoverEpsilon) {
      // The user scrolled on their own — hand the view back.
      _riding = false;
      return;
    }
    scrollToBottom(animate: false);
    _lastProgrammaticOffset = controller.position.pixels;
    WidgetsBinding.instance.addPostFrameCallback((_) => _rideTail());
  }

  /// Keep the answer's top pinned to the viewport top: every tick targets
  /// the same content position, so this is effectively a single move; tool
  /// messages inserted above the answer shift the target and the pin stays
  /// with the answer. A settled offset away from our last programmatic
  /// placement cancels the pin — the user took over.
  void _pinAnswerTop() {
    if (!_armed || !_streamingNow) return;
    if (!controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return;
    }
    if (position.isScrollingNotifier.value) {
      // An animated scroll (e.g. the on-send follow) is still settling —
      // retry on the next tick instead of fighting it.
      return;
    }
    if ((position.pixels - _lastProgrammaticOffset).abs() >
        _userTakeoverEpsilon) {
      // The user scrolled on their own — no automatic moves for the rest
      // of the stream.
      _armed = false;
      return;
    }
    final anchorContext = streamAnchorKey.currentContext;
    final box = anchorContext?.findRenderObject();
    final viewport = box is RenderBox
        ? RenderAbstractViewport.maybeOf(box)
        : null;
    if (viewport == null || box == null) {
      // Bubble not laid out yet — try again on the next tick.
      return;
    }
    final target = viewport
        .getOffsetToReveal(box, 0.0)
        .offset
        .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() > 1) {
      controller.jumpTo(target);
      _lastProgrammaticOffset = target;
    }
  }

  /// Handle structural list changes: jump to bottom on a container switch;
  /// otherwise follow newly-added items when the user forced it (they just
  /// sent a message) or is already near the bottom.
  void handleStructural({
    required int itemCount,
    String? containerId,
    bool forceFollow = false,
  }) {
    if (containerId != _lastContainerId) {
      _lastContainerId = containerId;
      _lastItemCount = itemCount;
      _streamId = null;
      _armed = false;
      _riding = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom(animate: false);
      });
      return;
    }

    if (itemCount != _lastItemCount) {
      // While a stream is pinned or being ridden, structural inserts (tool
      // calls/results mid-answer) must not yank the view to the bottom —
      // the streaming handler owns the scroll position until it's done.
      final shouldScroll = !_armed && !_riding && (forceFollow || isNearBottom);
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
    // Record the placement so takeover detection can tell our scrolls from
    // the user's; only reachable positions count (an animated scroll never
    // jumps its target).
    if (target >= 0) _lastProgrammaticOffset = target;
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
