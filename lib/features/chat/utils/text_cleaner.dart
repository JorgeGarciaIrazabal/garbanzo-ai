/// Strips markdown formatting and emojis from text so TTS reads cleanly.
String cleanTextForSpeech(String text) {
  var cleaned = text;

  // Remove code blocks (``` ... ```) entirely
  cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), '');

  // Remove inline code backticks but keep the text inside
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'`([^`]*)`'),
    (m) => m.group(1) ?? '',
  );

  // Remove image syntax ![alt](url)
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (m) => m.group(1) ?? '',
  );

  // Convert links [text](url) to just the text
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1) ?? '',
  );

  // Remove markdown headings (# ... ######)
  cleaned = cleaned.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

  // Remove bold/italic markers (*** ** * __ _)
  cleaned = cleaned.replaceAll(RegExp(r'\*{1,3}'), '');
  cleaned = cleaned.replaceAll(RegExp(r'_{1,3}'), ' ');

  // Remove strikethrough
  cleaned = cleaned.replaceAll(RegExp(r'~~'), '');

  // Remove horizontal rules
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true),
    '',
  );

  // Remove blockquote markers
  cleaned = cleaned.replaceAll(RegExp(r'^>\s?', multiLine: true), '');

  // Remove bullet point markers
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*[-*+]\s+', multiLine: true),
    '',
  );

  // Remove numbered list prefixes but keep the text
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*\d+\.\s+', multiLine: true),
    '',
  );

  // Remove HTML tags
  cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');

  // Remove common emojis (Unicode emoji ranges)
  cleaned = cleaned.replaceAll(
    RegExp(
      r'[\u{1F600}-\u{1F64F}]' // emoticons
      r'|[\u{1F300}-\u{1F5FF}]' // misc symbols & pictographs
      r'|[\u{1F680}-\u{1F6FF}]' // transport & map
      r'|[\u{1F1E0}-\u{1F1FF}]' // flags
      r'|[\u{2702}-\u{27B0}]' // dingbats
      r'|[\u{1F900}-\u{1F9FF}]' // supplemental symbols
      r'|[\u{1FA00}-\u{1FA6F}]' // chess symbols
      r'|[\u{1FA70}-\u{1FAFF}]' // symbols extended-A
      r'|[\u{2600}-\u{26FF}]' // misc symbols
      r'|[\u{2700}-\u{27BF}]' // dingbats
      r'|[\u{FE00}-\u{FE0F}]' // variation selectors
      r'|[\u{200D}]' // zero-width joiner
      r'|[\u{20E3}]' // combining enclosing keycap
      r'|[\u{E0020}-\u{E007F}]', // tags
      unicode: true,
    ),
    '',
  );

  // Collapse excessive whitespace
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  cleaned = cleaned.replaceAll(RegExp(r'  +'), ' ');

  return cleaned.trim();
}
