# Admin

Admin-only area for running the server. Regular users don't see it.

## How do accounts get created?
Public sign-up is disabled. An admin creates accounts in Admin → Users,
which can also disable accounts or grant admin.

## How do I connect an MCP tool server?
Admin → MCP Servers: add the server's connection details and use
**Test connection**. These are **global** servers — their tools appear in
everyone's Skills library. (Individual users can also connect their own
private servers from Settings → Tools; those are visible only to that user.)

## How do I manage which models are available?
Admin → Models syncs the model list from the LLM backend (Ollama) and lets
you enable/disable individual models for users.

## Where do user bug reports and feature requests go?
Admin → Reports lists everything submitted via "Report a bug or idea" in
the settings drawer. Filter by status and move each report through
Open → In progress → Closed from its status chip.
