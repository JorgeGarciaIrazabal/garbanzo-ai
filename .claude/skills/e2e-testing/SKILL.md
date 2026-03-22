---
name: e2e-testing
description: E2E testing workflow for the Flutter app using MCP tools
---

# E2E Testing with Marionette + Dart MCP

## Workflow Overview

```
1. Start backend          → FastAPI on port 8000
2. Launch Flutter app     → via Dart MCP (launch_app) → get VM service URI
3. Connect Marionette     → connect(uri: <vm_service_uri>)
4. Interact + assert      → tap / enter_text / take_screenshots / get_logs
5. Inspect widget tree    → Dart MCP get_widget_tree / get_runtime_errors
6. Stop                   → Dart MCP stop_app
```

## Step 1 — Start the Backend

```bash
just be-dev
```

Verify it's up at `http://localhost:8000/health` before proceeding.

## Step 2 — Launch the Flutter App via Dart MCP

```
list_devices                     → pick "linux" (desktop — always preferred)
launch_app(device_id: "linux")   → returns { dtd_uri, vm_service_uri, pid }
```

The `vm_service_uri` will look like `ws://127.0.0.1:PORT/ws`. Save it — you need it for Marionette.

> **Note:** Always use `linux` desktop device. Chrome requires browser port randomness workarounds and Flutter web integration tests are not supported on `-d chrome`.

## Step 3 — Connect Marionette

```
connect(uri: "<vm_service_uri from launch_app>")
```

Marionette is now linked to the running Flutter app.

## Step 4 — Discover UI Elements

```
get_interactive_elements()
```

Elements are matched by `ValueKey<String>` (more reliable) or by text content. If an element is missing, add a `ValueKey` to it in the source code and hot_reload.

## Step 5 — Interact with the App

| Action | Tool | Notes |
|--------|------|-------|
| Tap a button / element | `tap(key: "submit_button")` or `tap(text: "Send")` | Keys preferred |
| Type into a field | `enter_text(key: "message_input", text: "Hello")` | Targets focused field |
| Scroll | `scroll_to(key: "message_list")` | Scrolls element into view |
| Screenshot | `take_screenshots()` | Check current UI state |
| Read logs | `get_logs()` | Debug print statements, errors |
| Hot reload after code change | `hot_reload()` | Preserves app state |

## Step 6 — Inspect with Dart MCP

```
connect_dart_tooling_daemon(uri: "<dtd_uri from launch_app>")
get_widget_tree()         → full widget hierarchy
get_runtime_errors()      → Dart/Flutter errors
get_app_logs()            → structured app output
```

Use `get_widget_tree` to find widget keys and verify rendering. Use `get_runtime_errors` after interactions to assert no crashes occurred.

## Step 7 — Stop the App

```
stop_app(pid: <pid from launch_app>)
# or: Dart MCP stop_app
```

---

# App UI Reference Guide

This section documents the UI structure, element matching strategies, and common workflows to avoid repeated iteration on element locations.

## Matching Strategies

**Prefer text matching** for most elements. Marionette's `tap(text: "...")` and `enter_text(focused_element: true, ...)` work reliably.

**Use coordinates** when text matching fails (e.g., for TextFormFields without labels):

| Element | Bounds (center) | Notes |
|---------|----------------|-------|
| Login email field | (640, 368) | First TextFormField on login page |
| Login password field | (640, 432) | Second TextFormField on login page |
| Login submit button | (640, 498) | FilledButton below password |
| Register email field | (640, 400) | Second TextFormField on register page |
| Register password field | (640, 464) | Third TextFormField on register page |
| Register submit button | (640, 530) | FilledButton at bottom |

**Use tooltip matching** for IconButtons:

| Tooltip | Action |
|---------|--------|
| "Settings" | Open settings drawer |
| "Account menu" | Open account popup menu (logout) |
| "Attach file" | Open file picker |
| "Voice input" | Start/stop voice recording |
| "Stop generation" | Stop streaming response |

---

## Login Page (`LoginPage`)

### Elements
- **Email field**: `TextFormField` — first text field, centered horizontally
- **Password field**: `TextFormField` — second text field, below email
- **Sign in button**: `FilledButton` — with text "Sign in"
- **Create account link**: `TextButton` — with text "Create an account"

### Login Flow
```
1. tap(coordinates: {x: 640, y: 368})  # Focus email field
2. enter_text(focused_element: true, input: "user@example.com")
3. tap(coordinates: {x: 640, y: 432})  # Focus password field
4. enter_text(focused_element: true, input: "password123")
5. tap(coordinates: {x: 640, y: 498})  # Tap Sign in button
```

### Error Messages
- **"Incorrect email or password"**: Invalid credentials — appears as red text above the Sign in button
- **"Enter your email"**: Empty email validation error
- **"Enter your password"**: Empty password validation error

### Create Account Navigation
```
tap(text: "Create an account")  # Navigate to register page
```

---

## Register Page (`RegisterPage`)

### Elements
- **Full name field**: `TextFormField` — optional, first field
- **Email field**: `TextFormField` — second field
- **Password field**: `TextFormField` — third field, with hint "At least 6 characters"
- **Create account button**: `FilledButton` — with text "Create account"
- **Sign in link**: `TextButton` — with text "Already have an account? Sign in"

### Register Flow
```
1. tap(coordinates: {x: 640, y: 336})  # Focus full name (optional)
2. enter_text(focused_element: true, input: "Test User")
3. tap(coordinates: {x: 640, y: 400})  # Focus email field
4. enter_text(focused_element: true, input: "test@example.com")
5. tap(coordinates: {x: 640, y: 464})  # Focus password field
6. enter_text(focused_element: true, input: "password123")
7. tap(coordinates: {x: 640, y: 530})  # Tap Create account button
```

---

## Chat Page (`ChatPage`)

### Layout Overview
```
┌─────────────────────────────────────────────────────────────┐
│ [☰] [Conversation Title]        [Model ▼] [⚙️] [👤]        │ ← AppBar
├───────────────┬─────────────────────────────────────────────┤
│               │                                             │
│  [New Chat]   │                                             │
│               │         (Message Area)                       │
│ Conversation  │                                             │
│    List       │    "Start a conversation"                   │
│               │    [Suggestion Chips]                       │
│               │                                             │
├───────────────┴─────────────────────────────────────────────┤
│ [📎] [🎤] [Type a message...                    ] [➤]      │ ← Input
└─────────────────────────────────────────────────────────────┘
```

### AppBar Elements
| Element | Type | Location | Action |
|---------|------|----------|--------|
| Menu button (mobile) | `IconButton` | Leading | Open conversation drawer (mobile only) |
| Title | `Text` | Center | Shows conversation title or "New Chat" |
| Model selector | `DropdownButton` | Actions area | Select LLM model |
| Settings | `IconButton` (tooltip: "Settings") | Actions area | Open settings drawer |
| Account menu | `IconButton` (tooltip: "Account menu") | Actions area | Show logout option |

### Sidebar (Conversation List)
| Element | Text/Type | Action |
|---------|-----------|--------|
| New Chat button | FilledButton "New Chat" | Create new conversation |
| Conversation item | `InkWell` with title + "N messages" | Select conversation |
| Delete button | `IconButton` (trash icon) | Delete conversation (with confirmation dialog) |

### Message Input Area
| Element | Type | Action |
|---------|------|--------|
| Attach file | `IconButton` (tooltip: "Attach file") | Open file picker |
| Voice input | `IconButton` (tooltip: "Voice input") | Start/stop recording |
| Message field | `TextField` (hint: "Type a message...") | Enter message text |
| Send button | `IconButton` (send icon) | Send message |
| Stop button | `IconButton` (stop icon) | Stop streaming (appears during generation) |

### Empty State
- Text: "Start a conversation"
- Subtitle: "Type a message below to begin chatting"
- Suggestion chips (ActionChip):
  - "Explain quantum computing"
  - "Write a Python function"
  - "Help me debug code"

### Sending a Message
```
1. tap(text: "Explain quantum computing")  # Tap suggestion chip, OR:
2. tap(coordinates: {x: 792, y: 683})       # Focus text field
3. enter_text(focused_element: true, input: "Hello, AI!")
4. tap(coordinates: {x: 1240, y: 684})       # Tap send button (right side)
```

### Creating New Conversation
```
tap(text: "New Chat")  # In sidebar
```

### Selecting a Conversation
```
tap(text: "Conversation Title")  # Tap the conversation in the sidebar
```

### Deleting a Conversation
```
1. Find conversation in sidebar
2. tap(type: "IconButton") on the conversation row (trash icon)
3. tap(text: "Delete")  # Confirm in dialog
```

---

## Settings Drawer (`SettingsDrawer`)

### Opening Settings
```
tap(type: "IconButton")  # with tooltip "Settings"
# or tap(coordinates: {x: 1212, y: 28})  # Settings gear icon
```

### Settings Sections

#### Appearance Section
- **Theme toggle**: `SegmentedButton` with "Light" / "Dark" / "System"
  - Match by text: `tap(text: "Dark")` or `tap(text: "Light")`

#### Chat Section
- **Show message metadata**: `SwitchListTile` — toggle for token counts/response time

#### Model Section
- **LLM Model dropdown**: Shows current model name (e.g., "Qwen3 Coder Next (cloud)")
  - Tap to open dropdown, then tap model name to select

#### Memory Section
- **View memories**: `ListTile` — navigate to MemoryPage
  ```
  tap(text: "View memories")
  ```
- **Use memory toggle**: `SwitchListTile` — enables memory injection (requires active conversation)

#### Text-to-Speech Section
- **Voice dropdown**: Select TTS voice (e.g., "Heart (English)")
- **Speed slider**: `Slider` (0.5x to 2.0x)
- **Auto-play responses**: `SwitchListTile` — auto-read assistant messages

#### Speech Input Section
- **Auto-send after transcription**: `SwitchListTile`

### Closing Settings
```
tap(type: "IconButton")  # Close button (X) in drawer header
# or swipe the drawer closed
# or tap outside the drawer
```

---

## Memory Page (`MemoryPage`)

### Navigation
From settings drawer:
```
tap(text: "View memories")
```

### Elements
- **AppBar**: Title "Memories", + button to create
- **Memory list**: Cards with edit/delete buttons
- **Create FAB**: `FloatingActionButton` with + icon
- **Create dialog**: TextField + "Cancel" / "Create" buttons
- **Edit dialog**: TextField + "Cancel" / "Save" buttons
- **Delete dialog**: "Cancel" / "Delete" buttons

### Creating a Memory
```
1. tap(type: "FloatingActionButton")  # Or tap + in AppBar
2. enter_text(focused_element: true, input: "My memory content")
3. tap(text: "Create")
```

### Editing a Memory
```
1. tap(icon: edit icon) on the memory card
2. enter_text(focused_element: true, input: "Updated content")
3. tap(text: "Save")
```

### Deleting a Memory
```
1. tap(icon: delete icon) on the memory card
2. tap(text: "Delete")  # Confirm in dialog
```

### Back Navigation
```
# Use navigator pop - may need coordinates for back button
tap(coordinates: {x: 40, y: 28})  # Back arrow in AppBar
```

---

## Account Menu

### Opening
```
tap(type: "IconButton")  # with tooltip "Account menu"
```

### Options
- **Sign out**: PopupMenuItem with text "Sign out"

### Logout Flow
```
1. tap(type: "IconButton")  # Account menu (person icon)
2. tap(text: "Sign out")
# Returns to login page
```

---

## Common Workflows

### Complete Login → Send Message Flow
```
# 1. Login
tap(coordinates: {x: 640, y: 368})  # Email field
enter_text(focused_element: true, input: "test@example.com")
tap(coordinates: {x: 640, y: 432})  # Password field
enter_text(focused_element: true, input: "password123")
tap(text: "Sign in")

# 2. Wait for chat page (verify "New Chat" appears)
get_interactive_elements()  # Should show "New Chat" FilledButton

# 3. Send a message
tap(text: "Explain quantum computing")  # Or type custom message

# 4. Verify response started
get_interactive_elements()  # Should show "Stop generation" button
```

### Register → Settings → Memory Flow
```
# 1. Register
tap(text: "Create an account")
tap(coordinates: {x: 640, y: 336})  # Full name (optional)
enter_text(focused_element: true, input: "Test User")
tap(coordinates: {x: 640, y: 400})  # Email
enter_text(focused_element: true, input: "test@example.com")
tap(coordinates: {x: 640, y: 464})  # Password
enter_text(focused_element: true, input: "password123")
tap(text: "Create account")

# 2. Open settings
tap(type: "IconButton")  # Settings gear

# 3. Navigate to memories
tap(text: "View memories")

# 4. Create memory
tap(type: "FloatingActionButton")
enter_text(focused_element: true, input: "Test memory content")
tap(text: "Create")
```

### Verify Message Appears in Conversation
```
# After sending a message
get_interactive_elements()
# Look for conversation title in sidebar
# Check for "1 messages" (or N messages) under conversation title
```

### Verify Error State
```
# After a failed action (e.g., wrong password)
get_interactive_elements()
# Look for error text like "Incorrect email or password"
# Error appears as Text widget with red color
```

---

## Troubleshooting

### Element Not Found
1. Use `take_screenshots()` to see current screen state
2. Use `get_interactive_elements()` to list all interactive elements
3. Try coordinate-based tapping as fallback
4. Add `ValueKey` to the widget in source and `hot_reload()`

### Timing Issues
- Use `get_interactive_elements()` to verify page loaded before interacting
- Check for loading indicators (CircularProgressIndicator) before proceeding

### Text Field Focus
- Always tap a text field before using `enter_text(focused_element: true, ...)`
- If tap fails, try coordinates: `tap(coordinates: {x: center_x, y: center_y})`

### Dropdown Selection
1. Tap the dropdown to open it
2. Wait for options to appear
3. Tap the desired option by text

---

## Key References

| Service | Value |
|---------|-------|
| Backend API | `http://localhost:8000` |
| API base URL (debug) | `http://localhost:8000` (hardcoded in `lib/core/api_client.dart`) |
| Override API URL | `--dart-define=API_BASE_URL=https://...` |

## Widget ValueKey Recommendations

For easier E2E testing, consider adding these keys to widgets:

```dart
// Login page
TextFormField(key: const ValueKey('email_field'), ...)
TextFormField(key: const ValueKey('password_field'), ...)
FilledButton(key: const ValueKey('login_button'), ...)

// Chat input
TextField(key: const ValueKey('message_input'), ...)
IconButton(key: const ValueKey('send_button'), ...)
IconButton(key: const ValueKey('attach_button'), ...)

// Conversation list
FilledButton(key: const ValueKey('new_chat_button'), ...)
```