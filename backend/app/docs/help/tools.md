# Tools & Skills

Tools let the assistant act — search, fetch data, schedule things — instead
of only talking. Tool calls and their results appear inline in the chat as
expandable activity cards.

## What tools are there?
- **Built-in tools** — always available, e.g. saving memories, creating
  scheduled actions, running micro-apps, app help, and submitting a bug
  report or feature request.
- **MCP tools** — external tool servers (Model Context Protocol). These come
  in two kinds: **global** servers an admin connects for everyone, and
  **personal** servers you connect just for yourself in Settings → Tools.

## Where can I see all available tools?
The **Skills library** page lists every connected tool with its
description; **Show schema** displays the exact parameters a tool accepts.

## How do I control which tools a conversation may use?
The conversation's tools setting defaults to **All tools**; you can restrict
it to a subset or none. Room agents have the same per-agent setting.

## Why did the assistant show a Confirm/Cancel card?
Some actions — creating a room, changing the conversation's style — are
never executed by the assistant directly. It proposes them, and the card
lets you confirm or cancel. Nothing happens until you press **Confirm**.

## Can the assistant create a room or change settings for me?
Yes — ask in chat ("create a room with Ana and a research agent", "use a
different model for this chat"). You'll get a confirmation card; the action
runs only after you confirm it.

## How do I ask for a specific tool?
Type `#` in the chat input bar and pick the tool from the suggestions —
sending a `#tool_name` mention tells the assistant explicitly to use that
tool. Smaller models especially benefit from the nudge.

## Why didn't the model use a tool?
Only tool-capable models can call tools (wrench badge in the model picker).
Explicitly asking ("use the … tool") usually helps.

## How do I add a new MCP tool server?
For your own use, go to **Settings → Tools → My MCP servers** and add the
server's connection details (transport, URL or command, optional auth). Only
you can see and use the tools from a personal server. Admins add **global**
servers for everyone in the Admin area — see the Admin guide.
