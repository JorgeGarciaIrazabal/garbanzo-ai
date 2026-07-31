# Changelog

Release notes for Garbanzo AI. Each entry is generated automatically on
`just deploy` — an LLM (via opencode) writes it from the release's commits and
the user reports it addressed. See `scripts/changelog-instructions.md`.

## v1.0.24 — 2026-07-31

### 🐛 Fixes
- Restored the Ollama web-search MCP tool.

## v1.0.23 — 2026-07-31

- No user-facing changes.

## v1.0.22 — 2026-07-31

- No user-facing changes.

## v1.0.21 — 2026-07-30

- add configurable GPU voice inference

## v1.0.20 — 2026-07-30

- No user-facing changes.

## v1.0.19 — 2026-07-28

### ✨ Features
- Improved chat recovery after disconnects and made agent activity indicators more reliable.

## v1.0.18 — 2026-07-28

### ✨ Features
- Added an Android share target, so you can share text, links, and images from other apps straight into a new Garbanzo chat.

## v1.0.17 — 2026-07-25

### 🙋 User requests completed
- Set any style — including built-in presets — as the default for new conversations.
- Moved conversation search into the Android conversation list and added a "New chat" button to the header.
- Made recurring scheduled actions post into the same chat, keeping all of an action's history in one place.

### ✨ Features
- Allowed built-in styles to be used as the default for new chats while keeping their content read-only.
- Added mobile search inside the conversation list and a "New chat" button in the chat header on Android.
- Reused an existing conversation for recurring scheduled actions instead of creating a new one each run.

### 🐛 Fixes
- Replaced cryptic chat-stream error messages with friendly, readable explanations when the AI service is unavailable or a connection fails.
- Stopped background conversation sync from showing noisy error dialogs for transient connection hiccups.

## v1.0.16 — 2026-07-25

### 🙋 User requests completed
- Fixed micro-apps integration on Android so micro-app panels load reliably and show a retry card if the page fails.
- Fixed the micro-app panel showing "not found" after edits by re-syncing the underlying worktree before serving.

### 🐛 Fixes
- Ensured the assistant always produces a reply when it runs out of tool-call turns by synthesizing a fallback message.
- Improved micro-app handling on Windows by adding an inline WebView2 panel instead of opening the browser.
- Fixed the micro-app panel resize handle so dragging right widens the panel.
- Steered the assistant toward calling the micro-app tool directly with your request, reducing wasted tool iterations.

## v1.0.15 — 2026-07-25

### 🙋 User requests completed
- Fixed choppy text-to-speech timing by synthesizing speech continuously and prefetching audio before sentence boundaries.
- Added guardrails so long text-to-speech sessions no longer crash the server.

### 🐛 Fixes
- Smoothed Talk Mode speech transitions and applied language preferences more consistently to Whisper transcription.
- Bound TTS inference memory to prevent long playback sessions from exhausting server resources.
- Fixed a handful of minor issues.

## v1.0.14 — 2026-07-24

### 🐛 Fixes
- Improved Android Talk Mode audio handling and prompts.

## v1.0.13 — 2026-07-23

### 🙋 User requests completed
- Fixed chat not syncing across Android, web, and Windows until the app was fully refreshed.
- Fixed the Android audio playback error that could interrupt message playback.

### 🐛 Fixes
- Made audio playback and chat sync more reliable across platforms.

## v1.0.12 — 2026-07-23

### 🙋 User requests completed
- Fixed speech-to-text transcripts taking too long to appear after you finished speaking.
- Fixed Talk Mode translating non-English speech into English instead of transcribing the original words.

### 🐛 Fixes
- Preserved TTS start and auto-listen behavior in Talk Mode.
- Improved multilingual speech-to-text transcription, reducing latency and keeping non-English speech in its original language.

## v1.0.11 — 2026-07-23

### 🙋 User requests completed
- Fixed the frontend assertion error "BlockParser.parseLines is not advancing" that could crash the chat surface.
- Improved the quality of automatically extracted memories.

### ✨ Features
- Added workload-specific default model selection, so each task type picks the right model by default.

### 🐛 Fixes
- Fixed duplicate markdown block syntaxes in rendered messages.

## v1.0.10 — 2026-07-20

### ✨ Features
- Added an `/agent` composer command that sends complex tasks straight to a detached workflow runner, with a folder-editing mode and a read-only research mode.
- Added folder attachments for desktop chats, so the assistant can read files on demand while the folder stays on your device.
- Added detached workflow runs for complex folder tasks: the agent works on a server-side snapshot and returns a diff you review before applying locally.
- Added automatic error reports.

### 🐛 Fixes
- Fixed completed workflow runs restarting when the run card re-rendered.
- Fixed workflow run cards not appearing in chat and removed the upfront confirmation gate so runs start automatically.
- Fixed create-room and set-style action cards disappearing after reloading a conversation.
- Fixed the assistant not knowing the name of the folder you attached.
- Fixed workflow diffs including internal tool files and added warnings when large files are skipped.

## v1.0.9 — 2026-07-19

### ✨ Features
- Shipped six built-in styles — including Concise and Truth Seeker — as one-tap cards above your own saved styles
- Removed the Coding / Programación built-in style
- Reordered the styles list so your saved styles appear before built-in presets
- Updated the style picker to filter built-ins by your active locale and simplified its search/filter UI
- Split the Styles section into "Your styles" and "Predefined" headings

## v1.0.8 — 2026-07-19

### ✨ Features
- Added central style and prompt management in the chat style picker, including model selection, system prompt templates, and shortcuts to create, edit, and share custom prompts.
- Simplified Settings by moving model and system prompt choices into the chat style picker.
- Added automatic installation of the Android APK on a connected device after deployment.

### 🐛 Fixes
- Fixed built-in prompt templates so they display in the app's current language instead of mixing locales.


## v1.0.7 — 2026-07-18

### ✨ Features
- Added personal MCP servers in Settings → Tools; admins can still manage global servers shared with everyone, while personal servers are private to your own chats.
- Improved opt-in location sharing so it resolves your neighbourhood instead of just your city, and the assistant now suggests turning on location only when the question needs it.

### 🐛 Fixes
- Fixed menus and action buttons breaking in non-English languages by using stable internal keys instead of translated labels.
- Fixed the style picker bottom sheet appearing behind the Android navigation bar.


## v1.0.6 — 2026-07-18

### ✨ Features
- Added Spanish translations for the built-in system prompt templates (Coding Assistant, Writing Coach, Funny Friend, Emotional Expert, Socratic Tutor, and Brainstorm Partner).
- Localized dozens of hardcoded English labels and messages across settings, chat, memories, usage, login, profile, password, and system-prompt editing.
- Made the app title localize correctly on startup.

### 🐛 Fixes
- Fixed the "Type a message…" placeholder in the chat input so it translates properly instead of always appearing in English.



## v1.0.5 — 2026-07-17

### 🐛 Fixes
- Fixed styling when selecting a model.

## v1.0.4 — 2026-07-17

### ✨ Features
- Added an in-app bug and feature report form, a Reports triage tab for admins, and the ability for the assistant to file reports directly from chat. Admins are now notified when a new report arrives.
- Added automatic desktop update checks and installs: a banner alerts you when a newer build is available, Settings has a new "Software update" section, and the installer downloads and swaps in the latest version on Linux and Windows.
- Saved chat styles, system prompt templates, scheduled actions, and room agents can now be edited from their respective lists.
- Room agents gained a thinking-level selector and saved prompt templates in the add/edit dialog.
- Moved the Talk Mode call button into the chat composer, next to the dictation mic.
- Talk Mode replies now follow the language you speak in; pin a reply language from the call bar, or enable automatic language switching and choose preferred languages in Voice settings.
- Added Spanish, French, Hindi, Italian, and Brazilian Portuguese Kokoro voices, with language-aware voice swapping so the backend picks a voice that speaks the requested language.

### 🐛 Fixes
- Fixed desktop voice barge-in firing on faint sounds; added a Voice interruption sensitivity setting with Off, Low, Normal, and High options.
- Fixed an Android voice bug where speech detection would never stop after you finished talking, leaving transcription stuck.
- Fixed the update-available banner failing to open the changelog dialog.

## v1.0.3 — 2026-07-17

### ✨ Features
- Added preferred spoken languages and an auto-detect language toggle in settings.
- Speech-to-text now defaults to real auto-detect instead of forcing a fixed language, and supports per-request language overrides.

### 🐛 Fixes
- Hardened chat reload and push-notification deep-linking edge cases so paging deep into history and logging back in no longer causes silent failures or stale redirects.
- Fixed desktop release builds sometimes shipping with an empty API URL, which left them unable to connect to the live backend.
- Enforced a non-null message sequence in the database so a stray null row can no longer appear as the newest message.


## v1.0.2 — 2026-07-17

### 🙋 User requests completed
- Stopped Talk Mode replies from playing twice when “Auto-play responses” was enabled.
- Collapsed thinking/reasoning boxes by default in chat and rooms so they stay out of the way until you expand them.

### ✨ Features
- Added a style picker that bundles model, thinking level, and system prompt into one reusable style.
- Saved custom styles with a default option, and showed the active style name in the app bar.
- Added per-conversation thinking level control.
- Added a dynamic `<context>` block to chat prompts with the user’s timezone and local time, and included it for room agents in UTC for privacy.
- Added an opt-in coarse-location setting so the context block can include city-level location; raw coordinates are never stored.
- Reported device timezone and locale to the backend to feed the context block.
- Added friends: send/accept/decline requests, a friends page, notifications for requests and accepts, and block/unblock with privacy guard.
- Added prompt-template and tool autocomplete (`/` and `#`) in the composer, plus `@` mention autocomplete in rooms.
- Shared saved styles and prompt templates with friends.
- Added room member picking from your friends list when creating rooms and sending invites.
- Added native tools that ask before acting: action proposals now appear as Confirm/Cancel cards, and confirmed create-room cards offer an “Open room” deep link.
- Added `app_help`, an in-app assistant that answers “how do I…” questions from the new user guide.
- Added room notification muting for 8 hours, 1 week, or forever.
- Rebuilt Talk Mode as a call screen with live captions, barge-in carry-over, acoustic echo cancellation on Linux/mobile, transient-error auto-resume, and a mute + hang-up bar.

### 🐛 Fixes
- Fixed large conversations loading slowly: only the most recent messages are fetched on open, with more loaded on scroll-up.
- Fixed all notification types so tapping them navigates to the right place instead of just opening the app.
- Fixed partial streamed replies being lost when the client disconnected mid-stream; the recovered reply now replaces the raw error.
- Fixed the system prompt template dropdown crashing when users had custom templates.
- Fixed mention parsing so multi-word agent names are recognized correctly without matching shorter names inside them.


## v1.0.1 — 2026-07-15

### 🙋 User requests completed
- Stopped Windows from reading messages aloud when the read-aloud option is turned off.
- Used the Garbanzo brand icon consistently across Windows and Android.

### ✨ Features
- **Voice conversations with Talk Mode:** Hands-free back-and-forth voice chats — the app listens while you speak, transcribes your words, and replies out loud. Tap-to-talk, tap-to-interrupt, and auto-detect via voice activity detection are all supported.
- **Live micro-app editing inside chat:** The model can open one of your micro-apps in a side-by-side (or full-screen) live editor panel, run a local dev server, and apply edits through an agent so you see changes instantly.
- **Rooms for multi-person chat:** Create public or private rooms, add members, and chat with multiple agents and people in one shared thread. Supports file attachments, markdown rendering, typing indicators, and reconnecting websockets.
- **Knowledge base RAG with citations:** Attach documents to a conversation and ask questions grounded in them; source filenames appear as chips under the assistant's answer.
- **Long-term memory:** The app can extract facts from conversations, store them as user memories with semantic search, and recall them automatically in future chats.
- **Streamlined chat UX:** Sentence-by-sentence spoken replies, tool-progress indicators, auto-titling, jump-to-bottom scrolling, conversation search, a refreshed settings drawer, and a new Garbanzo brand identity across light and dark themes.
- **Web search and MCP tools:** Built-in web search plus an extensible tool layer for models, with per-user rate limiting on chat, TTS, and STT endpoints.
- **Web URLs and deep linking:** Proper URL routes on web and mobile so conversations and pages are linkable and the browser back button behaves as expected.

