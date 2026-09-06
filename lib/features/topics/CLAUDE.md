# Dynamic Context Topics — Agent Context

This feature owns the primary-chat topic discovery map and Active Context UI.
Import it through `package:garbanzo_ai/features/topics/...`; chat widgets own
the shell and conversation stream, not topic state.

## Layout

- `models/` — topic tree and active-context API values.
- `services/` — REST clients for topic graph and active-context mutations.
- `providers/` — loading, navigation path, selection, and optimistic state.
- `widgets/` — responsive topic field/landing, selectable hierarchy, and the Active Context panel.

## UX and state contracts

- The landing map is a responsive visual hierarchy: importance can affect size and treatment, while subtopics must remain visibly related and directly selectable. It uses no connecting edges on mobile.
- Selecting a parent may begin a conversation at that broad topic; selecting a child retains the real child topic ID. Selecting a topic hides the landing completely so chat has the full viewport.
- The chat sidebar/drawer still owns Threads. A user must be able to select historical threads without treating them as topics.
- `TopicDiscoveryProvider` may form a conservative local display group for obvious flat label families only. It is not persisted and must not override server graph topology or IDs.
- `ActiveContextProvider` controls only current dynamic context. Do not add an Activity view to it.

## Change checklist

Run `just fe-test test/chat/active_context_provider_test.dart test/chat/topic_discovery_provider_test.dart test/models/active_context_test.dart test/models/topic_node_test.dart test/widgets/dynamic_context_widgets_test.dart` and `just fe-lint`. Add tests for changed navigation, hierarchy, selection, or optimistic mutation behavior. Update `docs/architecture.md` and the in-app topics help when user-facing behavior changes.
