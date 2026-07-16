/// Returns the subset of [toolNames] mentioned as `#name` tokens in [text]
/// (word-start tokens only, source order, deduplicated).
List<String> mentionedToolNames(String text, Iterable<String> toolNames) {
  final seen = <String>{};
  return [
    for (final name in toolNames)
      if (seen.add(name) &&
          RegExp(
            '(^|\\s)#${RegExp.escape(name)}(\$|[^\\w])',
            multiLine: true,
          ).hasMatch(text))
        name,
  ];
}

/// Appends the tool-nudge hint for `#tool` mentions to an outgoing chat
/// message, so the model is told explicitly which tools the user pointed
/// at. Returns [text] unchanged when [mentioned] is empty.
String appendToolHint(String text, List<String> mentioned) {
  if (mentioned.isEmpty) return text;
  final names = mentioned.map((n) => '`$n`').join(', ');
  final plural = mentioned.length > 1 ? 's' : '';
  return '$text\n\n(Please use the $names tool$plural for this.)';
}

/// Bolds mention tokens (`@name`) in a markdown source string so message
/// bubbles render them highlighted without a custom markdown extension.
///
/// A token is a trigger char at start-of-text/after-whitespace followed by
/// non-whitespace. Trailing punctuation stays outside the bold so "@Ana,"
/// renders as "**@Ana**,". Already-emphasized tokens (`**@Ana**`) don't
/// match — the leading `*` isn't whitespace.
String boldMentionTokens(String text, {String trigger = '@'}) {
  final pattern = RegExp(
    '(^|\\s)(${RegExp.escape(trigger)}\\S+)',
    multiLine: true,
  );
  return text.replaceAllMapped(pattern, (m) {
    var token = m.group(2)!;
    var suffix = '';
    final punct = RegExp(r'[.,!?;:)\]]+$').firstMatch(token);
    if (punct != null) {
      suffix = punct.group(0)!;
      token = token.substring(0, token.length - suffix.length);
    }
    if (token.length <= trigger.length) return m.group(0)!;
    return '${m.group(1)}**$token**$suffix';
  });
}
