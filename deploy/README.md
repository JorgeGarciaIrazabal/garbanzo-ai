# Production Deployment

The prod stack is a self-contained Docker Compose project (`garbanzo-prod`),
fully isolated from dev: its own PostgreSQL, its own volumes, its own network.
Public access goes through an auto-restarting **ngrok** container tunneling the
reserved static domain to the backend — no host ngrok agent involved.

```
just deploy          # ship local main: web build → image → stack → health → APK
just deploy-model MODEL # pull one model into the production Ollama volume
just deploy-status   # compose ps + local & public health
just deploy-logs     # tail all logs (or: just deploy-logs backend|postgres|ngrok)
just deploy-restart  # restart services (keeps data)
just deploy-down     # stop the stack (keeps volumes/data)
```

`just deploy` snapshots the **local `main` branch** into a temporary git
worktree and builds everything from it, so you can run it from any branch with
a dirty tree. Each deploy also tags `garbanzo-backend:<short-sha>` and drops an
APK at `dist/garbanzo-ai-<short-sha>.apk` with the ngrok URL baked in — web and
Android hit the same backend simultaneously.

Every deploy also generates a release changelog: `opencode` reads this release's
git log plus the user reports it addressed and prepends a section (User requests
completed / Features / Fixes) to `CHANGELOG.md`, which is committed with the
version bump and used as the GitHub Release body. It's best-effort — if opencode
or its model isn't available, a raw commit list is written instead and the deploy
proceeds. Set `CHANGELOG_OPENCODE_MODEL` in `.env` to override the model.

## First-time setup

1. **ngrok** — create an account, reserve a static domain
   (dashboard.ngrok.com → Domains), copy your authtoken.
2. **Config** — `cp deploy/.env.example deploy/.env` and fill it in.
   `deploy/.env` is gitignored; it is the only place prod secrets live.
3. **Credentials on disk** (both are gitignored, checked by `just deploy`):
   - `backend/firebase-service-account.json` — FCM push notifications
     (mounted read-only into the container).
   - `android/app/google-services.json` — required for the APK build.
4. **SSH key** — `GIT_SSH_KEY_PATH` must point to a private key with push
   access to the micro-apps repo, `chmod 600` (it is mounted read-only; the
   container publishes as that GitHub user).
5. **Ollama** — runs as its own container (`ollama`, `ollama_data` volume),
   fully isolated from any host Ollama install. On first deploy, pull the
   models the app needs:
   ```
    just deploy-model llama3.2
    just deploy-model granite4:micro
    just deploy-model nomic-embed-text
    ```
     Cloud models (e.g. `glm-5.3:cloud`, `glm-5.3-flash:cloud`, `kimi-k3:cloud`,
     `deepseek-v4-flash:cloud`, `deepseek-v4-pro:cloud`, `gemma4:cloud`,
     `nemotron-3-ultra:cloud`,
     `nemotron-3-super:cloud`, `qwen3.5:cloud`)
     require a **one-time** `ollama signin` inside the container: run
     `docker compose -f deploy/docker-compose.yml --env-file deploy/.env exec ollama ollama signin`
     and confirm the printed URL in a browser while logged into ollama.com. The
     sign-in binds to the key in the `ollama_data` volume, so it survives
     redeploys — only wiping the volume requires signing in again. Local-only
     models work without it. After signing in, pull each cloud model:
     ```
     just deploy-model glm-5.3:cloud
     just deploy-model glm-5.3-flash:cloud
     just deploy-model kimi-k3:cloud
     just deploy-model deepseek-v4-flash:cloud
     just deploy-model deepseek-v4-pro:cloud
     just deploy-model gemma4:cloud
     just deploy-model nemotron-3-ultra:cloud
     just deploy-model nemotron-3-super:cloud
     just deploy-model qwen3.5:cloud
     ```
     Normal chats default to the multimodal `glm-5.3-flash:cloud`; automatic
     memory extraction and scheduled actions default to `glm-5.3:cloud`.
     Migration 037 upgrades the app's retired MiniMax M3, GLM 5.2, dated
     DeepSeek V4 Flash/Pro preview aliases, Kimi K2.7 Code, and Qwen 3.6
     identifiers in persisted user configurations and pending shared-style
     snapshots. The generic DeepSeek V4 Flash selection stays on Flash; Pro is
     available as a separate higher-usage model. If
     Qwen 3.6 was installed, pull the corresponding Qwen 3.8 tag before the
     deploy (the common replacement is `ollama pull qwen3.8:27b`). Override
     the workload defaults independently
     with `DEFAULT_MODEL`, `MEMORY_EXTRACTION_MODEL`, and
     `SCHEDULED_ACTION_MODEL` in `deploy/.env`.
6. Merge your work to `main`, then run `just deploy`.

> The free ngrok plan allows **one agent session**. `just deploy` refuses to
> run while a host `ngrok` process is alive (`pkill -x ngrok` to stop it).

## What runs

| Service  | Image                    | Notes                                             |
|----------|--------------------------|---------------------------------------------------|
| postgres | pgvector/pgvector:pg16   | no host port, healthchecked, `postgres_data` vol  |
| ollama   | ollama/ollama:latest     | no host port, healthchecked, `ollama_data` vol    |
| backend  | garbanzo-backend:latest  | 127.0.0.1:8001 for smoke tests; serves web + API  |
| ngrok    | ngrok/ngrok:latest       | `https://$NGROK_DOMAIN` → backend:8000            |

All services use `restart: unless-stopped` — they survive crashes and host
reboots (as long as the Docker daemon starts on boot).

- **Migrations** run automatically at backend startup (`schema_migrations`
  table tracks applied files). A failing migration crash-loops the backend on
  purpose — check `just deploy-logs backend`.
- **Models** (Kokoro TTS + Whisper STT, ~2 GB) download on first boot into the
  `hf_cache` volume and persist across deploys. Voice features come up a few
  minutes after the first start.
- **Voice compute** defaults to CPU. On an NVIDIA host with Docker GPU support,
  set both `STT_DEVICE=cuda` and `TTS_DEVICE=cuda` in `deploy/.env`; `just
  deploy` installs a CUDA 12.6 Torch stack shared by Faster Whisper and Kokoro
  and grants the backend access to the GPU. Leave both as `cpu` elsewhere.
- **Micro-apps**: the repo is cloned into the `microapps_repo` volume on first
  boot and synced every `MICROAPPS_PULL_INTERVAL_MINUTES` (default 10): fetch,
  fast-forward main, rebase *clean* user worktrees. The panel is served through
  the backend's authenticated `/micro-apps` reverse proxy (single tunnel), and
  Publish pushes to GitHub with the mounted SSH key.

## Operations

**Rollback** — every deploy tags the image with the git SHA:

```bash
docker tag garbanzo-backend:<old-sha> garbanzo-backend:latest
just deploy-restart
```

(`docker images garbanzo-backend` lists what you have.)

**psql escape hatch**:

```bash
docker compose -f deploy/docker-compose.yml --env-file deploy/.env \
  exec postgres psql -U garbanzo -d garbanzo_ai_prod
```

**Old prod data** — the pre-redesign database volume
(`garbanzo-ai_postgres_prod_data`) was left untouched. To resurrect it into
the new stack: `just deploy-down`, then

```bash
docker run --rm \
  -v garbanzo-ai_postgres_prod_data:/from:ro \
  -v garbanzo-prod_postgres_data:/to \
  alpine sh -c "rm -rf /to/* && cp -a /from/. /to/"
```

then set `POSTGRES_PASSWORD=garbanzo_prod` in `deploy/.env` (the copied volume
keeps its original credentials) and `just deploy` again.

**Wipe prod completely**:

```bash
just deploy-down
docker volume rm garbanzo-prod_postgres_data garbanzo-prod_hf_cache garbanzo-prod_microapps_repo
```
