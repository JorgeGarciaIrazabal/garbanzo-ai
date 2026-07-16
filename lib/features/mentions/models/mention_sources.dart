/// Builders that turn data the app already holds into [MentionCandidate]
/// lists, plus the shared filter/ranking used by the overlay.
///
/// All functions are pure — fetching/refreshing stays with the existing
/// providers (FriendsProvider, RoomProvider, ToolProvider, …); the compose
/// bars pass in whatever those currently hold.
library;

import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_candidate.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/tools/models/mcp_tool.dart';

/// `@` in a room: human members first, then agents.
List<MentionCandidate> roomMentionCandidates(Room room) => [
  for (final m in room.members)
    MentionCandidate(
      kind: MentionKind.member,
      id: m.userId,
      label: m.displayName,
      sublabel: m.displayName == m.userId ? null : m.userId,
      insertText: '@${m.displayName}',
    ),
  for (final a in room.agents.where((a) => a.isActive))
    MentionCandidate(
      kind: MentionKind.agent,
      id: a.id,
      label: a.name,
      sublabel: a.model,
      insertText: '@${a.name}',
    ),
];

/// `@` outside a room (future sharing surfaces): accepted friends.
List<MentionCandidate> friendMentionCandidates(List<Friend> friends) => [
  for (final f in friends)
    MentionCandidate(
      kind: MentionKind.friend,
      id: f.email,
      label: f.displayName,
      sublabel: f.displayName == f.email ? null : f.email,
      insertText: '@${f.email}',
    ),
];

/// `/` in chat: prompt templates.
List<MentionCandidate> templateMentionCandidates(
  List<SystemPromptTemplate> templates,
) => [
  for (final t in templates)
    MentionCandidate(
      kind: MentionKind.template,
      id: t.id,
      label: t.name,
      sublabel: t.description,
      insertText: '/${t.name}',
    ),
];

/// `#` in chat: enabled MCP + native tools.
List<MentionCandidate> toolMentionCandidates(List<MCPTool> tools) => [
  for (final t in tools)
    MentionCandidate(
      kind: MentionKind.tool,
      id: '${t.serverId}:${t.name}',
      label: t.name,
      sublabel: t.serverName,
      insertText: '#${t.name}',
    ),
];

/// Filters and ranks [candidates] for [query]: label-prefix matches first,
/// then label-substring, then sublabel matches; ties keep source order
/// (stable sort). Case-insensitive. Empty query returns everything.
List<MentionCandidate> filterMentionCandidates(
  List<MentionCandidate> candidates,
  String query, {
  int limit = 8,
}) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return candidates.take(limit).toList();

  int rank(MentionCandidate c) {
    final label = c.label.toLowerCase();
    if (label.startsWith(q)) return 0;
    if (label.contains(q)) return 1;
    if ((c.sublabel?.toLowerCase().contains(q)) ?? false) return 2;
    return -1;
  }

  // Dart's List.sort is not stable, so break rank ties on source index.
  final ranked = <(int, int, MentionCandidate)>[
    for (final (i, c) in candidates.indexed)
      if (rank(c) >= 0) (rank(c), i, c),
  ];
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });
  return [for (final (_, _, c) in ranked.take(limit)) c];
}
