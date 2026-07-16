import 'package:flutter/material.dart';

/// A [TextEditingController] that renders mention tokens (`@name`,
/// `/template`, `#tool`) in the composer with the theme's primary color so
/// inserted mentions read as tokens, not plain text.
///
/// Purely presentational — the text value stays plain, so nothing else
/// (drafts, submission, backend) needs to know about mentions.
class MentionTextController extends TextEditingController {
  MentionTextController({super.text, Set<String>? triggers})
    : triggers = triggers ?? const {'@', '/', '#'};

  /// Trigger chars that begin a highlighted token.
  final Set<String> triggers;

  /// A token: a trigger char at start-of-text/after-whitespace followed by
  /// at least one non-whitespace char. The leading whitespace (if any) is
  /// part of the match — no lookbehind, which older Safari lacks — and is
  /// re-emitted unstyled in [buildTextSpan].
  RegExp get _tokenPattern {
    final chars = triggers.map(RegExp.escape).join();
    return RegExp('(^|\\s)[$chars]\\S+', multiLine: true);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // While IME composing is active, defer to the default rendering —
    // mixing composing underlines with our spans breaks the ranges.
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final tokenStyle = (style ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    final children = <TextSpan>[];
    var last = 0;
    for (final match in _tokenPattern.allMatches(text)) {
      final tokenStart = match.start + match.group(1)!.length;
      if (tokenStart > last) {
        children.add(TextSpan(text: text.substring(last, tokenStart)));
      }
      children.add(
        TextSpan(
          text: text.substring(tokenStart, match.end),
          style: tokenStyle,
        ),
      );
      last = match.end;
    }
    if (children.isEmpty) return TextSpan(style: style, text: text);
    if (last < text.length) {
      children.add(TextSpan(text: text.substring(last)));
    }
    return TextSpan(style: style, children: children);
  }
}
