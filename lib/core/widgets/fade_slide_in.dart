import 'package:flutter/material.dart';

import 'package:garbanzo_ai/core/motion.dart';

/// Plays a one-shot fade + slight upward slide when the widget mounts.
///
/// Used for message-appear animations in chat and rooms: new list items get
/// a fresh element and animate in; existing items keep their state and stay
/// put. Rebuilds of a mounted item (e.g. streaming updates) don't replay.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child});

  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.medium,
  )..forward();

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.easeOut,
  );

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
