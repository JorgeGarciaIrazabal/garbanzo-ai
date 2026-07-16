import 'package:flutter/widgets.dart';

/// An in-progress mention being typed: the trigger char, the query after
/// it, and the token's range in the text (trigger included).
class MentionQuery {
  const MentionQuery({
    required this.trigger,
    required this.query,
    required this.start,
    required this.end,
  });

  /// The trigger character (`@`, `/`, `#`…).
  final String trigger;

  /// Text between the trigger and the cursor.
  final String query;

  /// Offset of the trigger char.
  final int start;

  /// Cursor offset (exclusive end of the token).
  final int end;

  @override
  bool operator ==(Object other) =>
      other is MentionQuery &&
      other.trigger == trigger &&
      other.query == query &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(trigger, query, start, end);
}

/// Finds the mention being typed at the cursor, if any.
///
/// A mention token is a run of non-whitespace that *starts* with a trigger
/// char, where the run begins the text or follows whitespace. The cursor
/// must sit inside/at the end of that run (a collapsed selection). The
/// query may itself contain trigger chars (emails: `@ana@example.com`).
MentionQuery? activeMentionQuery(
  String text,
  TextSelection selection,
  Set<String> triggers,
) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  final cursor = selection.baseOffset;
  if (cursor < 1 || cursor > text.length) return null;

  // Walk back to the start of the current non-whitespace run.
  var start = cursor;
  while (start > 0 && !_isWhitespace(text[start - 1])) {
    start--;
  }
  if (start == cursor) return null; // cursor right after whitespace
  final first = text[start];
  if (!triggers.contains(first)) return null;

  return MentionQuery(
    trigger: first,
    query: text.substring(start + 1, cursor),
    start: start,
    end: cursor,
  );
}

/// Replaces [query]'s token with [insertText] plus a trailing space and
/// puts the cursor after it.
TextEditingValue insertMention(
  TextEditingValue value,
  MentionQuery query,
  String insertText,
) {
  final text = value.text;
  final replaced =
      '${text.substring(0, query.start)}$insertText '
      '${text.substring(query.end)}';
  final cursor = query.start + insertText.length + 1;
  return TextEditingValue(
    text: replaced,
    selection: TextSelection.collapsed(offset: cursor),
  );
}

bool _isWhitespace(String ch) => ch.trim().isEmpty;
