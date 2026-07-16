import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_candidate.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_sources.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/tools/models/mcp_tool.dart';

Room _room({List<RoomMember> members = const [], List<RoomAgent> agents = const []}) {
  return Room(
    id: 'r1',
    name: 'Room',
    description: null,
    ownerId: 'me@example.com',
    isPublic: false,
    maxAgentTurnDepth: 3,
    mode: 'chat',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    memberCount: members.length,
    agentCount: agents.length,
    members: members,
    agents: agents,
  );
}

RoomMember _member(String email, {String? fullName}) => RoomMember(
  roomId: 'r1',
  userId: email,
  fullName: fullName,
  role: 'member',
  joinedAt: DateTime.utc(2026),
);

RoomAgent _agent(String name, {bool isActive = true}) => RoomAgent(
  id: 'agent-$name',
  roomId: 'r1',
  name: name,
  avatar: null,
  provider: 'ollama',
  model: 'llama3',
  systemPrompt: null,
  responseMode: 'mention',
  turnOrder: 0,
  isActive: isActive,
  isModerator: false,
  enabledTools: null,
  createdAt: DateTime.utc(2026),
);

void main() {
  group('roomMentionCandidates', () {
    test('lists members then active agents with @ insert text', () {
      final room = _room(
        members: [_member('ana@example.com', fullName: 'Ana')],
        agents: [_agent('Scribe'), _agent('Ghost', isActive: false)],
      );

      final out = roomMentionCandidates(room);

      expect(out.map((c) => c.label), ['Ana', 'Scribe']);
      expect(out.first.kind, MentionKind.member);
      expect(out.first.insertText, '@Ana');
      expect(out.first.sublabel, 'ana@example.com');
      expect(out.last.kind, MentionKind.agent);
      expect(out.last.sublabel, 'llama3');
    });

    test('member without full name gets no redundant sublabel', () {
      final out = roomMentionCandidates(
        _room(members: [_member('bo@example.com')]),
      );
      expect(out.single.label, 'bo@example.com');
      expect(out.single.sublabel, isNull);
    });
  });

  test('friendMentionCandidates inserts the email, not the name', () {
    final out = friendMentionCandidates(const [
      Friend(email: 'ana@example.com', friendshipId: 'f1', fullName: 'Ana'),
    ]);
    expect(out.single.label, 'Ana');
    expect(out.single.insertText, '@ana@example.com');
  });

  test('templateMentionCandidates uses / and the template name', () {
    final out = templateMentionCandidates([
      SystemPromptTemplate(
        id: 't1',
        name: 'Concise',
        description: 'Short answers',
        content: '…',
        createdAt: DateTime.utc(2026),
      ),
    ]);
    expect(out.single.insertText, '/Concise');
    expect(out.single.sublabel, 'Short answers');
  });

  test('toolMentionCandidates uses # and a server-scoped id', () {
    final out = toolMentionCandidates(const [
      MCPTool(serverId: 'srv1', serverName: 'Search', name: 'web_search'),
    ]);
    expect(out.single.id, 'srv1:web_search');
    expect(out.single.insertText, '#web_search');
    expect(out.single.sublabel, 'Search');
  });

  group('filterMentionCandidates', () {
    const candidates = [
      MentionCandidate(
        kind: MentionKind.friend,
        id: '1',
        label: 'Ana Lopez',
        sublabel: 'ana@example.com',
        insertText: '@ana',
      ),
      MentionCandidate(
        kind: MentionKind.friend,
        id: '2',
        label: 'Banana Joe',
        sublabel: 'joe@example.com',
        insertText: '@joe',
      ),
      MentionCandidate(
        kind: MentionKind.friend,
        id: '3',
        label: 'Zoe',
        sublabel: 'zana@example.com',
        insertText: '@zoe',
      ),
    ];

    test('empty query returns everything up to the limit', () {
      expect(filterMentionCandidates(candidates, ''), hasLength(3));
      expect(
        filterMentionCandidates(candidates, '', limit: 2).map((c) => c.id),
        ['1', '2'],
      );
    });

    test('prefix beats substring beats sublabel', () {
      final out = filterMentionCandidates(candidates, 'ana');
      expect(out.map((c) => c.id), ['1', '2', '3']);
    });

    test('is case-insensitive and drops non-matches', () {
      final out = filterMentionCandidates(candidates, 'ZOE');
      expect(out.map((c) => c.id), ['3']);
    });

    test('ties keep source order', () {
      const tied = [
        MentionCandidate(
          kind: MentionKind.tool,
          id: 'a',
          label: 'search_web',
          insertText: '#search_web',
        ),
        MentionCandidate(
          kind: MentionKind.tool,
          id: 'b',
          label: 'search_docs',
          insertText: '#search_docs',
        ),
      ];
      expect(
        filterMentionCandidates(tied, 'search').map((c) => c.id),
        ['a', 'b'],
      );
    });
  });
}
