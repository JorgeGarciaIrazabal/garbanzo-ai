# Chat

## How do I start a new conversation?
Press **New Chat** at the top of the conversation list (the left sidebar on
desktop, the drawer on mobile).

## Do conversations sync across my devices?
Yes. While the app is open, the conversation list and the chat you are viewing
refresh automatically within about ten seconds of a change made on another
signed-in device. Returning to the app also refreshes them immediately. A reply
that is currently streaming on the local device is left untouched.

## How do I send a message?
Type in the input bar and press Enter (or the send button). While the
assistant is replying you can press the stop button to cancel generation.

## What do / and # do in the input bar?
Typing `/` at the start of a word suggests prompt templates and the **Agent**
command. Picking a template pastes its content into the field. Use `/agent`
followed by a task to force the autonomous agent instead of a normal chat
response. Typing `#`
suggests available tools; picking one inserts a `#tool_name` mention that
nudges the assistant to use that tool for your request. Use the arrow keys
and Enter (or tap) to pick a suggestion; Esc dismisses it.

## How do I attach images or files?
Use the paperclip (**Attach photos or files**) next to the input bar. Images
are sent to vision-capable models; documents (PDF, text, etc.) have their
text extracted and included with your message.

On Android, you can also choose **Garbanzo AI** from another app's Share menu.
Shared pictures, files, and any accompanying text are staged in the chat
composer so you can review them and add instructions before sending.

## How do I include a folder in a chat? (desktop)
On the desktop app, open the paperclip menu and choose **Folder**, or drag a
folder onto the chat. The assistant can then read files inside that folder on
demand (PDFs, spreadsheets, Word/PowerPoint, code, and plain text) as you ask
about them — it reads them only when relevant, and shows which file it is
reading. Access is strictly sandboxed: the assistant can **never** read
anything outside the folder you attached, and it never modifies those files on
its own — to change them, see delegating a task below. A chip above the input
bar shows the attached folder; tap its **×** to detach it. This option is
desktop-only — web can't reach your files.

## Can the assistant change files in my folder?
Not directly, but it can hand the job to an agent that does. When you ask for
something big — "refactor this module", "add tests across the package", "fix
every occurrence of X" — the assistant **delegates the task** to an autonomous
coding agent, and a line appears in the chat showing that it's working. Expand
that line to watch what the agent is doing.

Your own files are never at risk *while it works*: the app uploads a **copy** of
the attached folder and the agent only ever touches that copy. When it finishes,
the resulting changes are **written straight into your folder** — no review step
in between. There is no built-in undo yet, so keep anything precious under
version control (or a backup) if you want an easy way back.

Three things worth knowing:

- **It keeps running if you close the app.** The work happens on the server,
  so you can carry on elsewhere. If the app is closed when it finishes you
  get a notification; if you're still in the app you don't — the progress
  line and the summary in the conversation already tell you.
- **Your edits win.** If you change one of those files yourself while the agent
  is working, that file is reported as a conflict and skipped rather than
  overwritten.
- **Big folders are trimmed.** Hidden files, `.git`, and `node_modules` are
  never uploaded, and files over 5 MB are skipped. Expanding the progress
  line tells you when something was left out — the agent can't act on what
  it never received.

## Can I use the agent without attaching a folder?
Yes. Ask for deep research or another complex, multi-step task and the
assistant can delegate it with no folder attached. To force delegation, start
the message with `/agent`, for example `/agent deep research on the 2026 World
Cup`.

Folderless work runs on the server in an empty workspace, can use web research
and the MCP tools allowed in this conversation, and keeps running if you close
the app. It never reads or writes files on your device, so it works on web and
Android as well as desktop. When it finishes, use **Download** on the progress
line to export the markdown report (share sheet on web/Android, Save As on
desktop).

## Can it work on slides, spreadsheets, or images?
Your files come back **byte-for-byte intact** — a `.xlsx` or `.pptx` the agent
changed is still a valid, openable file, and binary files it didn't touch are
left alone. What's limited is how well the agent can *understand* them: it
reads files as text, so it can't view a slide deck the way you do. It works
best on code and text formats. It can still handle office files by scripting
them (for example with a spreadsheet library), but treat that as something to
review carefully rather than assume.

One practical limit: files over 5 MB aren't uploaded at all — which many real
decks exceed. The agent can still produce one (its output is written to your
folder on completion), but anything over 5 MB it generates is reported as
skipped rather than written.

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
