# Styles (model, thinking level, system prompt)

A **style** bundles a model, a thinking level, and a system prompt template
into one reusable preset (e.g. "Deep Work", "Quick Answers").

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
Pick a prompt template in the style picker's **Customize** section, or edit
the prompt directly from the system prompt banner above the chat. Use the
**+** button next to the template dropdown to create a new prompt (with AI
or from scratch) and the **✏️** button to edit a selected custom template.
See the System Prompts guide for details.

## How do I save a style?
Compose model + thinking + template in the picker's **Customize** section,
then press **Save style** and name it. Saved styles appear as cards in the
**Styles** section — tap one to apply everything at once.

## How do I make a style the default for new chats?
On the style's card, choose **Use for new chats**. New conversations start
with that style's thinking level and prompt; its model becomes your default
model. Without a default, your most recently applied style seeds new chats.

## How do I edit a style?
Open the style card's menu and choose **Edit…**. The picker switches to the
Customize section pre-filled with the style's model, thinking level, and
template — recompose freely (the current chat is untouched while editing),
then press **Save changes** to update it; the name and default flag can be
changed in the dialog. The × next to "Editing …" cancels without saving.

## How do I delete a style?
Open the style card's menu and choose Delete. This removes the saved preset
only — no conversations are affected.

## What do the badges on models mean?
- Eye: supports images (vision)
- Wrench: supports tools
- Brain: supports thinking
A faded badge under an active capability filter means the capability is
unknown for that model (it may still work).
