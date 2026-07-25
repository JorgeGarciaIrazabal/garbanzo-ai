/// Matches the backend's maximum text length for one TTS request.
const maxTtsRequestLength = 5000;

/// Split speech text into bounded chunks, preferring sentence and word
/// boundaries while guaranteeing that even unpunctuated text stays bounded.
List<String> splitTextForTts(
  String text, {
  int maxLength = maxTtsRequestLength,
}) {
  final chunks = <String>[];
  final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
  var current = '';

  void flushCurrent() {
    if (current.isNotEmpty) chunks.add(current);
    current = '';
  }

  void appendBounded(String value) {
    var remaining = value.trim();
    while (remaining.isNotEmpty) {
      if (current.isNotEmpty &&
          current.length + 1 + remaining.length <= maxLength) {
        current = '$current $remaining';
        return;
      }
      if (current.isNotEmpty) flushCurrent();
      if (remaining.length <= maxLength) {
        current = remaining;
        return;
      }

      var splitAt = remaining.lastIndexOf(' ', maxLength);
      if (splitAt <= 0) splitAt = maxLength;
      chunks.add(remaining.substring(0, splitAt).trim());
      remaining = remaining.substring(splitAt).trimLeft();
    }
  }

  for (final sentence in sentences) {
    appendBounded(sentence);
  }
  flushCurrent();
  return chunks;
}
