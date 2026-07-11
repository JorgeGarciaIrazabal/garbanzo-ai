import 'package:flutter/material.dart';

/// Keeps action rows quiet until pointed at. A non-zero resting opacity keeps
/// the buttons discoverable and tappable on touch screens, where hover never
/// fires. Shared by the main chat's message actions and room agent replies
/// so both fade in identically.
class RevealOnHover extends StatelessWidget {
  const RevealOnHover({super.key, required this.revealed, required this.child});

  final bool revealed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: revealed ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 150),
      child: child,
    );
  }
}
