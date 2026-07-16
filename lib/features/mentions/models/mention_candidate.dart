/// What kind of thing a mention suggestion points at. Determines the icon
/// and how the insertion text is built.
enum MentionKind { friend, member, agent, template, tool }

/// One row in the mention-autocomplete overlay (idea 6).
///
/// Candidates are built client-side from data the app already holds
/// (friends, room members/agents, prompt templates, MCP tools) — the lists
/// are small, so there is no autocomplete endpoint; see `mention_sources`.
class MentionCandidate {
  const MentionCandidate({
    required this.kind,
    required this.id,
    required this.label,
    required this.insertText,
    this.sublabel,
  });

  final MentionKind kind;

  /// Stable identity: email, agent id, template id, or `server:tool`.
  final String id;

  /// Primary display text (name).
  final String label;

  /// Secondary display text (email, model, description…).
  final String? sublabel;

  /// The text the composer inserts when this candidate is picked,
  /// including the trigger char (e.g. `@Ana`, `/Concise`, `#web_search`).
  final String insertText;

  @override
  bool operator ==(Object other) =>
      other is MentionCandidate && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}
