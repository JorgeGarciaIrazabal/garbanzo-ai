# Tools & Skills

Tools let the assistant act — search, fetch data, schedule things — instead
of only talking. Tool calls and their results appear inline in the chat as
expandable activity cards.

## What tools are there?
- **Built-in tools** — always available, e.g. saving memories, creating
  scheduled actions, running micro-apps, and app help.
- **MCP tools** — external tool servers connected by an admin (Model
  Context Protocol).

## Where can I see all available tools?
The **Skills library** page lists every connected tool with its
description; **Show schema** displays the exact parameters a tool accepts.

## How do I control which tools a conversation may use?
The conversation's tools setting defaults to **All tools**; you can restrict
it to a subset or none. Room agents have the same per-agent setting.

## Why didn't the model use a tool?
Only tool-capable models can call tools (wrench badge in the model picker).
Explicitly asking ("use the … tool") usually helps.

## How do I add a new MCP tool server?
Admins connect MCP servers in the Admin area — see the Admin guide.
