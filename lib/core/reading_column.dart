import 'package:flutter/material.dart';

/// Centers [child] in a reading column so wide desktop windows don't stretch
/// prose (or the composer) to unreadable line lengths. Shared by the main
/// chat and rooms so both line up on the same column.
class ReadingColumn extends StatelessWidget {
  const ReadingColumn({
    super.key,
    required this.child,
    this.maxWidth = 820,
    this.horizontalPadding = 16,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    );
  }
}
