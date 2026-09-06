# Topics and active context

The primary chat is one unified conversation where Garbanzo can keep related
context available across turns. Topics are derived from your messages and
legacy threads; they do not create a new conversation for every subject.
Separate threads remain available for conversations that should stay isolated.

## How do I choose a topic?

Open the Topics view and select a personal topic, or activate one from Explore.
The view opens directly on a colorful topic map. Larger topics are currently
more likely to be useful, while the varied positions make choices easy to scan
without implying a rigid list. A broad parent and a visible subtopic are both
selectable conversation starting points. Sub-topics only appear on the map
when they are highly relevant; less relevant ones are one tap away — open the
parent topic to browse its full list.
You can also activate a topic directly from the primary chat. A selected topic
is shown with its parent when it belongs to a topic hierarchy. Your selection
always stays put: Garbanzo never changes the active topic on its own, it only
suggests a switch through the drift banner. Pinning controls whether active
context items stay pinned across turns.

## What is active context?

Active context is the material selected for the next primary-chat turn. It can
include a validated topic assertion, a source message, a legacy thread, a
memory, a knowledge-base item, or an attachment. The "What's included" section
groups the material into an expandable tree — one branch per source type
(Memories, Messages, History, Knowledge) — so you can see exactly what is in
context at a glance. Each leaf shows why it is included and its approximate
token cost. Pinned items stay selected until you unpin or remove them; dynamic
items may change with the next turn. A pinned topic stays visible as a slim
banner above the chat so you always know what Garbanzo is focused on.

## Can I remove something from context?

Yes. Use the context panel to pin, unpin, exclude, or restore an item. An
exclusion is applied before context ranking, so the excluded source or
assertion is not quietly reintroduced by a later refresh. You can also start a
Fresh start: this clears the active topic and dynamic context without deleting
your messages. Choose whether to keep pinned items.

## Why does context say preparing or live?

New messages are processed into a small live evidence delta while you continue
typing. A background job periodically rebuilds dirty topics into an immutable,
evidence-grounded pack. `ready` means the latest pack is current; `live` means
new evidence is available on top of that pack; `preparing` means no current
pack is available yet. A reply is not blocked while a pack is being prepared:
the primary compiler uses recent coherent evidence within the configured token
budget and marks the response as a fallback when necessary.

## Is my history shared with another user or cloud model?

No source is eligible unless it belongs to your account and its conversation is
not deleted. Message edits/deletes and conversation deletion invalidate derived
topic evidence. Rejected assertions remain only as a bounded negative
guardrail, while explicit exclusions and expired assertions are omitted.
The pack materializer and security checks are deterministic and local to the
backend. A deployment administrator may explicitly configure a semantic
curator. It runs once for each dirty user, not once per topic, to improve topic
names, build selectable parent/subtopic paths up to three levels deep, and
extract typed context tied to exact message IDs.
Local-only mode blocks cloud-tagged models. Cloud curation requires
`cloud_allowed` and sends only a bounded, already filtered evidence manifest.
Its response must pass strict schema, evidence, ownership, merge, and hierarchy
validation or no semantic graph changes are written and safe deterministic
packs remain available.

## Do legacy threads change?

No. A legacy thread keeps its normal message history, summary, memory, and
knowledge-base context path. Topic SSE updates and active-context controls are
available only for the primary chat.

## What happens when I switch topics?

Switching to a new topic advances the conversation to a new session epoch.
Historical messages and evidence links are preserved intact in the database,
while the active chat view displays only the messages for the current session.
You can choose whether to carry over active facts to the new topic. If Garbanzo
notices the discussion shifting to another topic, an interactive drift banner
prompts you to switch context or stay in the current topic.

## What is shown in the Active Context panel and empty state?

Rather than overwhelming you with raw message transcripts or technical IDs, both the Structured Active Context card and the Active Context sidebar provide high-level, human-readable insights:
- **About This Topic**: A clear, synthesized sentence outlining the scope, purpose, and domain of the topic.
- **Information Included in Context**: High-level, declarative statements summarizing the established preferences, decisions, and criteria that will be fed into Garbanzo's context for upcoming turns.
- **Topic Hierarchy & Controls**: Clear parent domain relationships (e.g. `Real Estate & Housing` → `Guadarrama & Aranjuez Property Search`), topic locking against drift, and switch options.
