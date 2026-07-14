# Deploy — Agent Context

Self-contained production Docker Compose stack (project `garbanzo-prod`), fully
isolated from dev: its own PostgreSQL, volumes, and network. `README.md` here is
the human ops guide (first-time setup, rollback, psql, data recovery) — consult
it for procedures. This file is the agent quick reference.

## Commands (from repo root, via `just`)

- `just deploy` — ship local `main`: web build → backend image → stack → health → APK
- `just deploy-status` — compose ps + local & public health checks
- `just deploy-logs [backend|postgres|ngrok]` — tail prod logs
- `just deploy-restart` — restart services (keeps data); `just deploy-down` — stop (keeps volumes)

## Layout

- `docker-compose.yml` — services: **postgres** (pgvector), **backend** (image
  built by `just deploy`, `127.0.0.1:8001`), **ollama** (containerized, own
  volume), **ngrok** (tunnels the static domain to `backend:8000`).
- `.env` (gitignored) — all prod secrets. `.env.example` documents the keys.

## Gotchas

- Never commit `.env`; edit `.env.example` when adding a key.
- No secrets in the image — web is baked in, everything else comes from env.
- Migrations auto-apply at backend startup; on first deploy the `ollama` volume is
  empty, so pull the app's models into the container (see `README.md`).
- `MICROAPPS_PROXY_MODE` / `MICROAPPS_GIT_URL` are set here (not `backend/.env`).
