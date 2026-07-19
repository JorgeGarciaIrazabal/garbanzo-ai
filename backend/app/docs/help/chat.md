# Chat

## How do I start a new conversation?
Press **New Chat** at the top of the conversation list (the left sidebar on
desktop, the drawer on mobile).

## How do I send a message?
Type in the input bar and press Enter (or the send button). While the
assistant is replying you can press the stop button to cancel generation.

## What do / and # do in the input bar?
Typing `/` at the start of a word suggests your prompt templates — picking
one pastes its content into the field, ready to edit and send. Typing `#`
suggests available tools; picking one inserts a `#tool_name` mention that
nudges the assistant to use that tool for your request. Use the arrow keys
and Enter (or tap) to pick a suggestion; Esc dismisses it.

## How do I attach images or files?
Use the paperclip (**Attach photos or files**) next to the input bar. Images
are sent to vision-capable models; documents (PDF, text, etc.) have their
text extracted and included with your message.

## How do I include a folder in a chat? (desktop)
On the desktop app, open the paperclip menu and choose **Folder**, or drag a
folder onto the chat. The assistant can then read files inside that folder on
demand (PDFs, spreadsheets, Word/PowerPoint, code, and plain text) as you ask
about them — it reads them only when relevant, and shows which file it is
reading. Access is strictly sandboxed: the assistant can **never** read
anything outside the folder you attached, and for now it can only read
(not modify) those files. A chip above the input bar shows the attached folder;
tap its **×** to detach it. This option is desktop-only — web can't reach your
files.

## How do I dictate a message?
Press the microphone button in the input bar and speak; the recording is
transcribed into the input field. For fully hands-free conversation, see
Talk Mode.

## How do I edit a message I already sent?
Hover (or long-press) your message and choose **Edit**. Editing rewrites the
message, removes everything after it, and reruns the conversation from that
point (**Save & rerun**).

## How do I get a different answer?
Use **Regenerate** on the assistant's reply — it deletes that response and
generates a new one.

## How do I branch a conversation?
Use the fork button on any message to start a new conversation that shares
history up to that point. The original conversation is untouched.

## How do I search my conversations?
Use the search icon above the conversation list. Results match titles and
message content.

## How do I pin a conversation?
Open the conversation's context menu in the list and choose **Pin**. Pinned
conversations stay at the top. **Unpin** the same way.

## How do I mute a conversation?
Open the conversation's context menu and choose **Mute** — pick a duration
or mute forever. Muted conversations post normally but send no
notifications. A "Muted" badge shows in the list; unmute from the same menu.

## How do I delete a conversation?
From the conversation's context menu, choose **Delete conversation**. This
permanently removes the conversation and its messages.

## What is the context window indicator?
A small gauge near the input showing how much of the model's context the
conversation uses. Long conversations are automatically summarized in the
background so they keep fitting; the summary is shown in the chat as a
collapsible block.

## Why does the assistant know today's date or my location?
Every message includes background context: the current time, your local
timezone (reported automatically by the app), and — only if you enabled it
in Settings — your approximate (neighbourhood-level) location. See the
Settings guide for location sharing.
