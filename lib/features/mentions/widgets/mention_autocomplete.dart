import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:garbanzo_ai/features/mentions/models/mention_candidate.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_query.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_sources.dart';

/// Wraps a composer (any widget containing a TextField driven by
/// [controller] + [focusNode]) with mention autocompletion:
///
/// - typing a trigger char (a key of [sources]) at a word start opens a
///   suggestion panel floating above the composer;
/// - the query after the trigger filters candidates live
///   ([filterMentionCandidates]);
/// - ↑/↓ move the highlight, Enter/Tab insert, Esc dismisses (desktop);
///   tapping a row inserts (mobile);
/// - insertion replaces the token via [insertMention] and keeps focus.
///
/// The panel anchors to this widget, not the text cursor — cursor-rect
/// geometry is unreliable across IME/web, and above-the-composer is where
/// chat apps put it anyway.
class MentionAutocomplete extends StatefulWidget {
  const MentionAutocomplete({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.sources,
    required this.child,
    this.onMentionInserted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Trigger char → candidate list builder, evaluated each time that
  /// trigger's panel opens/filters (so live provider data stays fresh).
  final Map<String, List<MentionCandidate> Function()> sources;

  /// Called after a candidate's text has been inserted.
  final void Function(MentionCandidate candidate)? onMentionInserted;

  final Widget child;

  @override
  State<MentionAutocomplete> createState() => _MentionAutocompleteState();
}

class _MentionAutocompleteState extends State<MentionAutocomplete> {
  final _link = LayerLink();
  final _scroll = ScrollController();
  OverlayEntry? _overlay;

  // Dense two-line ListTile height, used to keep the keyboard highlight in
  // view. An estimate is fine — rows only vary by a few px.
  static const _rowExtent = 56.0;

  MentionQuery? _query;
  List<MentionCandidate> _candidates = const [];
  int _highlight = 0;

  bool get _isOpen => _overlay != null;

  // Composers (MessageComposer) put their own onKeyEvent on the focus node,
  // and the primary node's handler runs before any ancestor Focus — so an
  // open panel would lose Enter to "send". Post-frame (after the composer
  // installed its handler) we wrap it: mention keys first, then theirs.
  FocusOnKeyEventCallback? _wrappedHandler;
  FocusNode? _wrappedNode;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_recompute);
    widget.focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _installKeyWrapper());
  }

  void _installKeyWrapper() {
    if (!mounted || _wrappedNode == widget.focusNode) return;
    _uninstallKeyWrapper();
    final node = widget.focusNode;
    final prev = node.onKeyEvent;
    node.onKeyEvent = (n, event) {
      final result = _onKeyEvent(n, event);
      return result != KeyEventResult.ignored
          ? result
          : (prev?.call(n, event) ?? KeyEventResult.ignored);
    };
    _wrappedNode = node;
    _wrappedHandler = prev;
  }

  void _uninstallKeyWrapper() {
    _wrappedNode?.onKeyEvent = _wrappedHandler;
    _wrappedNode = null;
    _wrappedHandler = null;
  }

  @override
  void didUpdateWidget(covariant MentionAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_recompute);
      widget.controller.addListener(_recompute);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      WidgetsBinding.instance.addPostFrameCallback((_) => _installKeyWrapper());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_recompute);
    widget.focusNode.removeListener(_onFocusChange);
    _uninstallKeyWrapper();
    _hide();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus) _hide();
  }

  void _recompute() {
    final value = widget.controller.value;
    final query = activeMentionQuery(
      value.text,
      value.selection,
      widget.sources.keys.toSet(),
    );
    if (query == null) {
      _hide();
      return;
    }
    final source = widget.sources[query.trigger];
    final candidates = filterMentionCandidates(source!(), query.query);
    if (candidates.isEmpty) {
      _hide();
      return;
    }
    final queryChanged = query != _query;
    _query = query;
    _candidates = candidates;
    if (queryChanged || _highlight >= candidates.length) _highlight = 0;
    _show();
  }

  void _show() {
    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildPanel);
      Overlay.of(context).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _hide() {
    _overlay?.remove();
    _overlay = null;
    _query = null;
    _candidates = const [];
    _highlight = 0;
  }

  void _insert(MentionCandidate candidate) {
    final query = _query;
    if (query == null) return;
    widget.controller.value = insertMention(
      widget.controller.value,
      query,
      candidate.insertText,
    );
    _hide();
    widget.onMentionInserted?.call(candidate);
  }

  void _move(int delta) {
    _highlight = (_highlight + delta) % _candidates.length;
    if (_highlight < 0) _highlight += _candidates.length;
    _overlay?.markNeedsBuild();
    if (_scroll.hasClients) {
      // Keep the highlighted row inside the viewport.
      final top = _highlight * _rowExtent;
      final bottom = top + _rowExtent;
      final viewTop = _scroll.offset;
      final viewBottom = viewTop + _scroll.position.viewportDimension;
      double? target;
      if (top < viewTop) {
        target = top;
      } else if (bottom > viewBottom) {
        target = bottom - _scroll.position.viewportDimension;
      }
      if (target != null) {
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isOpen || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _insert(_candidates[_highlight]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildPanel(BuildContext context) {
    final width = (this.context.findRenderObject() as RenderBox?)?.size.width;
    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -4),
        showWhenUnlinked: false,
        // Taps inside the panel must not blur the TextField (blur closes
        // the panel before onTap lands).
        child: TextFieldTapRegion(
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                key: const Key('mention_suggestions'),
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _candidates.length,
                itemBuilder: (context, i) {
                  final c = _candidates[i];
                  return ListTile(
                    dense: true,
                    selected: i == _highlight,
                    leading: Icon(_iconFor(c.kind), size: 20),
                    title: Text(c.label, overflow: TextOverflow.ellipsis),
                    subtitle: c.sublabel == null
                        ? null
                        : Text(c.sublabel!, overflow: TextOverflow.ellipsis),
                    onTap: () => _insert(c),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(MentionKind kind) => switch (kind) {
    MentionKind.friend => Icons.person_outline,
    MentionKind.member => Icons.person_outline,
    MentionKind.agent => Icons.smart_toy_outlined,
    MentionKind.template => Icons.notes_outlined,
    MentionKind.tool => Icons.build_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Not itself focusable: just intercepts key events bubbling up from
      // the TextField while the panel is open.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}
