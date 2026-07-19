# Styles (model, thinking level, system prompt)

A **style** bundles a model, a thinking level, and a system prompt template
into one reusable preset (e.g. "Concise", "Truth Seeker"). The app ships six
**built-in styles** — Concise, Truth Seeker, Writing & Stories, Coding,
Tutoring, and Brainstorm — shown as one-tap cards at the top of the Styles
section in the style picker. They are read-only: tap to apply, or start
from the Customize section to save your own variant.

| Built-in | Model | Template | For |
|----------|-------|----------|-----|
| **Concise** | Minimax M3 | Concise | Short, direct answers |
| **Truth Seeker** | GLM 5.2 (medium thinking) | Truth Seeker | Verifies claims, cites sources |
| **Writing & Stories** | Minimax M3 | Writing Coach | Fiction + non-fiction writing |
| **Coding** | Kimi K2.7 Code | Coding Assistant | Software engineering |
| **Tutoring** | GLM 5.2 (medium thinking) | Socratic Tutor | Learns by guiding questions |
| **Brainstorm** | Minimax M3 | Brainstorm Partner | Generates varied ideas quickly |

Built-in styles surface in the app's current language (English or Spanish).
A built-in whose model isn't installed is hidden until the model is pulled —
the card simply doesn't appear, rather than showing a broken affordance.

## How do I change the model?
Tap the style pill in the chat app bar to open the style picker, switch to
the **Customize** section, and pick a model from the list. You can search by
name and filter by capability (vision / tools / thinking) using the chips
above the list; the same icons appear as badges on each model row.

## How do I control how long the model "thinks"?
In the style picker's Customize section, set the thinking level: Auto, Off,
Low, Medium, or High. It only applies to models that support thinking — the
control is disabled otherwise. The level is saved per conversation.

## How do I set a system prompt for a conversation?
Tap a built-in style (e.g. "Tutoring") to apply its prompt + model in one
tap, or compose your own in the Customize section. The **Prompt** dropdown
in Customize lists only your own custom templates — the built-in personas
are surfaced as built-in styles instead, so the dropdown keeps "create your
own" as its job. Use the **+** button next to the dropdown to create a new
prompt (with AI or from scratch) and the **✏️** button to edit a selected
custom template. See the System Prompts guide for details.

## How do I save a style?
Compose model + thinking + template in the picker's **Customize** section,
then press **Save style** and name it. Saved styles appear as cards in the
**Styles** section under the built-ins — tap one to apply everything at once.

## How do I make a style the default for new chats?
On your own style's card, choose **Use for new chats**. Built-in styles
can't be marked default — make your own copy (open the built-in, switch to
Customize, tweak if you like, then **Save style**) and default that. New
conversations start with the default style's thinking level and prompt; its
model becomes your default model. Without a default, your most recently
applied style seeds new chats.

## How do I edit a style?
Open your style card's menu and choose **Edit…**. The picker switches to the
Customize section pre-filled with the style's model, thinking level, and
template — recompose freely (the current chat is untouched while editing),
then press **Save changes** to update it; the name and default flag can be
changed in the dialog. The × next to "Editing …" cancels without saving.

Built-in styles have no menu: to tweak one, apply it, switch to Customize,
and save the result as your own style.

## How do I delete a style?
Open your style card's menu and choose Delete. This removes the saved preset
only — no conversations are affected. Built-ins can't be deleted.

## What do the badges on models mean?
- Eye: supports images (vision)
- Wrench: supports tools
- Brain: supports thinking
A faded badge under an active capability filter means the capability is
unknown for that model (it may still work).