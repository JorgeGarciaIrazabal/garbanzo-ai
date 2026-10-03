# Styles (model, thinking level, system prompt)

A **style** bundles a model, a thinking level, and a system prompt template
into one reusable preset (e.g. "Concise", "Truth Seeker"). The app ships five
**built-in styles** — Concise, Truth Seeker, Writing & Stories, Tutoring, and
Brainstorm — shown as one-tap cards under **Predefined** in the Styles
section in the style picker. They are read-only: tap to apply, or start
from the Customize section to save your own variant.

| Built-in | Model | Template | For |
|----------|-------|----------|-----|
| **Concise** | DeepSeek V4.1 Flash | Concise | Short, direct answers |
| **Truth Seeker** | DeepSeek V4.1 Flash (medium thinking) | Truth Seeker | Verifies claims, cites sources |
| **Writing & Stories** | DeepSeek V4.1 Flash | Writing Coach | Fiction + non-fiction writing |
| **Tutoring** | DeepSeek V4.1 Flash (medium thinking) | Socratic Tutor | Learns by guiding questions |
| **Brainstorm** | DeepSeek V4.1 Flash | Brainstorm Partner | Generates varied ideas quickly |

Built-in styles surface in the app's current language (English or Spanish).
A style whose model isn't installed shows a warning; install or enable its
model before applying it.

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
Open the style picker, choose **Styles → New style**, enter a name, and write
how you want the assistant to respond in **Instructions**. Press **Save** once.
There is no need to create or name a separate prompt template. Instructions
are optional; leave them empty for a style with only model/thinking settings.

The form starts from the current chat's settings. Expand **Model and thinking**
to change them, or **Start from an existing prompt** to reuse instructions.
You can also open the same form with **Save style** in Customize. Your saved
styles appear under **Your styles**, above the predefined ones; tap a card to
apply it. Creating or editing a style does not change the current chat.

## How do I make a style the default for new chats?
On any style card, choose **Use for new chats**, or enable it in the style
editor. Built-in styles can also be your default. New
conversations start with the default style's thinking level and prompt; its
model becomes your default model. Without a default, your most recently
applied style seeds new chats.

Opening a new topic (at startup or from the New topic button) uses that same
default style's model and prompt, with thinking reset to Medium. The composer
shows the style's name and a separate Medium thinking chip for models that
support reasoning. You can change the effort for the current chat; opening
another new topic resets it to Medium again.

## How do I edit a style?
Open your style card's menu and choose **Edit…**. The same form opens with
its name, instructions, model, thinking level and default setting. Edit and
press **Save**, or **Cancel** to discard the draft. Changing instructions here
does not change the original prompt template or other styles using it.
If saving fails, the draft stays open so you can retry.

To make your own version of a built-in style, apply it, then choose **New style**.

## How do I delete a style?
Open your style card's menu and choose Delete. This removes the saved preset
only — no conversations are affected. Built-ins can't be deleted.

## What do the badges on models mean?
- Eye: supports images (vision)
- Wrench: supports tools
- Brain: supports thinking
A faded badge under an active capability filter means the capability is
unknown for that model (it may still work).
