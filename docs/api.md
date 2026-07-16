# API Endpoint Reference

All endpoints are prefixed with `/api/v1/`. Auth uses the `get_current_user`
dependency validating `Authorization: Bearer <token>`. Keep this table current:
when you add or change an endpoint, update the matching row in the same commit.

| Group | Endpoints |
|-------|-----------|
| **Auth** | `POST /auth/login`, `POST /auth/register`, `GET /auth/me` |
| **Admin** | `POST /admin/users`, `GET /admin/users`, `PATCH /admin/users/{email}`, `GET /admin/mcp-servers`, `POST /admin/mcp-servers`, `PATCH /admin/mcp-servers/{id}`, `DELETE /admin/mcp-servers/{id}`, `POST /admin/mcp-servers/{id}/test-connection`, `GET /admin/models`, `POST /admin/models/sync`, `PATCH /admin/models` |
| **Chat** | `GET/POST /chat/conversations`, `GET /chat/conversations/search`, `GET /chat/conversations/{id}`, `PATCH /chat/conversations/{id}`, `PATCH /chat/conversations/{id}/mute`, `DELETE /chat/conversations/{id}`, `POST /chat/conversations/{id}/chat` (SSE stream), `POST /chat/conversations/{id}/messages/{mid}/regenerate`, `POST /chat/conversations/{id}/messages/{mid}/edit`, `POST /chat/conversations/{id}/messages/{mid}/branch`, `DELETE /chat/conversations/{id}/chat` (cancel stream), `GET /chat/models`, `GET /chat/health/llm` |
| **System Prompts** | `GET /system-prompts/templates`, `POST /system-prompts/templates`, `PATCH /system-prompts/templates/{id}`, `DELETE /system-prompts/templates/{id}`, `GET /system-prompts/user-default`, `PUT /system-prompts/user-default`, `POST /system-prompts/generate` (SSE stream) |
| **STT** | `POST /stt/transcribe`, `GET /stt/health` |
| **TTS** | `POST /tts/speak`, `POST /tts/speak/stream`, `GET /tts/voices`, `GET /tts/health` |
| **Memories** | `POST /memories`, `GET /memories`, `GET /memories/{id}`, `PATCH /memories/{id}`, `DELETE /memories/{id}` |
| **Knowledge Base** | `POST /kb/documents`, `GET /kb/documents`, `GET /kb/documents/{id}`, `DELETE /kb/documents/{id}`, `GET /kb/search` |
| **Rooms** | `POST /rooms`, `GET /rooms`, `GET /rooms/search`, `GET /rooms/{id}`, `PATCH /rooms/{id}`, `DELETE /rooms/{id}`, `GET /rooms/{id}/members`, `POST /rooms/{id}/members`, `DELETE /rooms/{id}/members/{email}`, `PATCH /rooms/{id}/members/me/mute`, `GET /rooms/{id}/agents`, `POST /rooms/{id}/agents`, `PATCH /rooms/{id}/agents/{id}`, `DELETE /rooms/{id}/agents/{id}`, `GET /rooms/{id}/messages`, `POST /rooms/{id}/chat`, `GET /rooms/{id}/export`, `WS /rooms/{id}` |
| **Micro-apps** | `POST /microapps/workspace`, `GET /microapps/workspace`, `DELETE /microapps/workspace`, `GET /microapps/apps`, `GET /microapps/houses`, `POST /microapps/houses`, `POST /microapps/agent/chat`, `POST /microapps/agent/abort`, `GET /microapps/changes`, `POST /microapps/publish`, `POST /microapps/revert` |
| **MCP (Tools)** | `GET /mcp/tools` |
| **Notifications** | `GET /notifications`, `GET /notifications/unread-count`, `POST /notifications/read-all`, `PATCH /notifications/{id}/read`, `DELETE /notifications/{id}`, `GET /notifications/preferences`, `PATCH /notifications/preferences` |
| **Devices** | `POST /devices/register`, `DELETE /devices/register` |
| **Scheduled Actions** | `POST /scheduled-actions`, `GET /scheduled-actions`, `GET /scheduled-actions/{id}`, `PATCH /scheduled-actions/{id}`, `DELETE /scheduled-actions/{id}` |
| **Styles** | `POST /styles`, `GET /styles`, `GET /styles/{id}`, `PATCH /styles/{id}`, `DELETE /styles/{id}` |
| **Usage** | `GET /usage/summary` |
| **Health** | `GET /health` |
