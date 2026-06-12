# Proposed Improvements Task List

This task list contains proposed improvements for the Garbanzo AI repository. It covers simplifications, user experience (UX) enhancements, new features, and infrastructure upgrades.

---

## 🛠️ Code Simplification & Refactoring

- [ ] **[Backend] Refactor `RoomConnectionManager` WebSocket Broker to Prevent Recursion**
  * *Current Issue*: When a websocket connection fails to send text, it calls `disconnect()`. `disconnect()` removes the socket and calls `broadcast_presence()`, which attempts to send the updated presence list to all remaining sockets. If another socket fails there, it calls `disconnect()` recursively.
  * *Improvement*: Avoid recursive calls by returning failed/dead connections from the broadcast loop, and performing a single cleanup and presence broadcast pass outside the loop.
- [ ] **[Backend] Move Pluggable LLM Provider Registration to Application Lifespan**
  * *Current Issue*: In `ChatService`, `_ensure_default_provider` is called on initialization, registering the `OllamaProvider` on every service instantiation.
  * *Improvement*: Move provider registration to the central FastAPI startup `lifespan` callback (in `main.py`) to avoid repeated, redundant provider registrations on every request.
- [ ] **[Frontend] Decouple Model and Chat Providers using `ProxyProvider`**
  * *Current Issue*: In `chat_page.dart`, `ModelProvider` is initialized first, and `ChatProvider` is initialized in a nested builder with a manual callback `selectedModelId: () => modelProvider.selectedModelId`.
  * *Improvement*: Use Flutter's `ProxyProvider` to inject `ModelProvider` updates automatically, simplifying the widget tree structure and removing manual callback delegation.
- [ ] **[Backend] Centralize Document Text Extraction Helpers**
  * *Current Issue*: PDF, CSV, spreadsheet, and text extraction logic is written inline within `chat_service.py`.
  * *Improvement*: Extract the base64 decoding and file parsing logic into a dedicated file-parsing utility service (e.g., `services/document_parser.py`) to maintain a clean separation of concerns.

---

## ✨ User Experience (UX) & Design (Wow Factors)

- [ ] **[Frontend] Implement Mermaid Diagram Rendering on Flutter Web**
  * *Current Issue*: The current `MermaidDiagram` widget relies on `webview_flutter`, which does not support web (`kIsWeb`). On Web, it falls back to a plain text code block.
  * *Improvement*: Implement interactive SVG rendering for Mermaid diagrams on web. Since the app is running in the browser, load `mermaid.js` in `web/index.html` and invoke rendering via Dart's JS interop (`dart:js_interop` / `package:web`) or wrapper `HtmlElementView`.
- [ ] **[Frontend] Premium Aesthetic & Theme Modernization**
  * *Current Issue*: Standard Material 3 styling can feel generic.
  * *Improvement*: Refine colors and shapes to offer a premium workspace feel:
    * Introduce subtle glassmorphism borders and container elevations.
    * Use curated font pairings (e.g., Outfit or Inter).
    * Implement custom gradients for chat headers and sidebar backgrounds.
- [ ] **[Frontend] Micro-Animations & Page Transitions**
  * *Current Issue*: Chat screen shifts and message appearances are immediate.
  * *Improvement*: Add subtle transitions:
    * Smooth scrolling/fading animations for new messages (`AnimatedList`).
    * Pulsing micro-animations for the thinking state and typing indicators.
    * Slide/fade transitions when opening dialogs, the settings drawer, or switching rooms.
- [ ] **[Frontend] Interactive Lightbox for Image Attachments**
  * *Current Issue*: Clicking image attachments opens a basic dialog.
  * *Improvement*: Use interactive viewer widgets (`InteractiveViewer`) to allow pinch-to-zoom, panning, and double-tap zoom for attached images.
- [ ] **[Frontend] Desktop Sidebar Collapse Toggle**
  * *Current Issue*: Sidebar is always visible on wide desktop screens.
  * *Improvement*: Allow toggling the sidebar open/closed on desktop to maximize chat area space.

---

## 🚀 New Feature Proposals

- [ ] **[Frontend & Backend] Conversation Folders & Tags**
  * *Description*: Allow users to organize chats into custom folders or apply metadata tags for filtering.
  * *Technical*: Update the DB schema (`Conversation` table) with folder/tag relationships, and support querying chats by folder/tag.
- [ ] **[Frontend & Backend] Message Reactions & Starring**
  * *Description*: Let users react with emojis (like thumbs up) or star/bookmark specific messages.
  * *Technical*: Add a `reactions` JSONB column or relationship to the `Message` database model.
- [ ] **[Frontend & Backend] Structured Multi-Agent Debate / Critique Mode**
  * *Description*: Create a structured room mode where two agents argue opposing viewpoints on a topic, and a third moderator agent evaluates and summarizes the discussion.
  * *Technical*: Implement a specialized debate controller within `RoomChatService` to cycle turns programmatically and invoke the judge agent.

---

## ⚙️ Infrastructure & Database Upgrades

- [ ] **[Backend] Database Schema Migrations (Alembic)**
  * *Description*: Replace manual SQL scripts in `backend/migrations/` with a formal Alembic migration flow.
  * *Benefit*: Standardizes migrations, prevents schema mismatch bugs, and allows automatic code-to-database schema diff detection.
- [ ] **[Backend] Distributed Connection Broker (Redis Integration)**
  * *Description*: Integrate Redis to cache active connection statuses, room presence, and model listings.
  * *Benefit*: Enables scaling the FastAPI backend horizontally across multiple processes or containers without losing WebSocket brokers.
- [ ] **[Backend] Asynchronous Worker Queue (arq or Celery)**
  * *Description*: Offload intensive operations to a background task queue.
  * *Use Cases*: Extracting memories daily, processing and indexing vector embeddings for the Knowledge Base.
- [ ] **[Backend] API Rate Limiting**
  * *Description*: Introduce rate-limiting middleware (e.g., token bucket) on the FastAPI router to protect LLM inference and TTS/STT endpoints from excessive requests.
