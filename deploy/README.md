# Production Deployment

The prod stack is a self-contained Docker Compose project (`garbanzo-prod`),
fully isolated from dev: its own PostgreSQL, its own volumes, its own network.
Public access can use **ngrok**, **Cloudflare Tunnel**, or both. Both connectors
run in the production Docker network and forward to `backend:8000`. Cloudflare
uses a remotely managed tunnel; the published application service URL in the
Cloudflare dashboard must be `http://backend:8000`. A DNS CNAME and tunnel UUID
alone do not connect the origin: the connector token is also required.

```
just deploy          # ship local main: web build → image → stack → health → APK
just deploy-model MODEL # pull one model into the production Ollama volume
just deploy-status   # compose ps + local & public health
just deploy-logs     # tail logs (or: just deploy-logs backend|postgres|ngrok|cloudflared)
just deploy-config-check # validate enabled connector configuration
just deploy-tunnel-up cloudflared # start Cloudflare beside the running backend
just deploy-test     # focused tunnel-selection tests
just deploy-restart  # restart services (keeps data)
just deploy-down     # stop the stack (keeps volumes/data)
```

`just deploy` snapshots the **local `main` branch** into a temporary git
worktree and builds everything from it, so you can run it from any branch with
a dirty tree. Each deploy also tags `garbanzo-backend:<short-sha>` and
`garbanzo-read-aloud:<short-sha>`, and drops an
APK at `dist/garbanzo-ai-<short-sha>.apk` with `PUBLIC_APP_URL` baked in — web and
Android hit the same backend simultaneously. The signed APK is also attached
to the version's GitHub Release; its signing key remains only on this host.

Every deploy also generates a release changelog: Codex reads the release's commit
subjects plus stable `Report-ID` commit trailers and prepends a section to
`CHANGELOG.md`, which is committed with the version bump and used as the GitHub
Release body. Raw report bodies and diagnostics are never included. Generation
is best-effort: if Codex or its model is unavailable, a deterministic commit list
is written and deployment continues. Set `CHANGELOG_CODEX_MODEL` in `.env` to
override the model.

The backend image records the exact source commit in its OCI revision label.
Deployment evidence keeps that source revision separate from the later release
commit; report-specific behavior must still be verified before a linked report
can close. Web, backend, and signed Android artifacts all build successfully
before the production Compose stack is replaced.

## First-time setup

1. **Public tunnel** — ngrok remains the default. For Cloudflare, create a
   remotely managed tunnel and a published application hostname. Set its service
   URL to `http://backend:8000`; obtain the connector token from the tunnel's
   **Install connector** screen. The token is secret; store it only in
   `deploy/.env`. A domain alone does not start the connector.
2. **Config** — `cp deploy/.env.example deploy/.env` and fill it in.
   `deploy/.env` is gitignored; it is the only place prod secrets live.
3. **Credentials on disk** (both are gitignored, checked by `just deploy`):
   - `backend/firebase-service-account.json` — FCM push notifications
     (mounted read-only into the container).
   - `android/app/google-services.json` — required for the APK build.
4. **Android release signing** — run `just deploy-android-signing-setup` once.
   It creates a permanent production keystore under the user's private config
   directory and writes its path, alias, and generated passwords to the
   gitignored `deploy/.env`. Back up both securely: APK updates must always use
   this same key. This does not require Google Play.
5. **GitHub CLI** — run `gh auth login` on the deploy host with write access to
   `GITHUB_REPO`. Deploy uses it only to create the release and upload the
   already-signed APK; Android build credentials never go to GitHub Actions.
6. **SSH key** — `GIT_SSH_KEY_PATH` must point to a private key with push
   access to the micro-apps repo, `chmod 600` (it is mounted read-only; the
   container publishes as that GitHub user).
7. **Ollama** — runs as its own container (`ollama`, `ollama_data` volume),
   fully isolated from any host Ollama install. On first deploy, pull the
   models the app needs:
   ```
    just deploy-model nomic-embed-text
   ```
     Cloud models (e.g. `deepseek-v4.1-flash:cloud`, `glm-5.3:cloud`,
     `glm-5.3-flash:cloud`, `kimi-k3:cloud`, `deepseek-v4-flash:cloud`,
     `deepseek-v4-pro:cloud`, `gemma4:cloud`, `nemotron-3-ultra:cloud`,
     `nemotron-3-super:cloud`, `qwen3.5:cloud`)
     require a **one-time** `ollama signin` inside the container: run
     `just deploy-ollama-signin`
     and confirm the printed URL in a browser while logged into ollama.com. The
     sign-in binds to the key in the `ollama_data` volume, so it survives
     redeploys — only wiping the volume requires signing in again. Local-only
     models work without it. After signing in, pull each cloud model:
     ```
     just deploy-model deepseek-v4.1-flash:cloud
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
     Normal chats default to the multimodal `deepseek-v4.1-flash:cloud`;
     automatic memory extraction and scheduled actions default to
     `deepseek-v4.1-flash:cloud` too. The built-in styles (Concise, Truth
     Seeker, etc.) also ride `deepseek-v4.1-flash:cloud`; only user-saved styles
     keep a model of their own choosing.
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
8. **Pocket read-aloud** — set a unique `READ_ALOUD_WORKER_TOKEN` (generate
   with `openssl rand -hex 32`) and an `HF_TOKEN` with access to the gated
   Spanish checkpoint and Lola reference in `deploy/.env`. The token stays in
   the worker container. The first start downloads models into dedicated named
   volumes and can take several minutes; the worker must report ready before
   the backend starts. The service has no public port and a 6 GiB RAM ceiling.
9. Commit the verified work on `main`, then run `just deploy`.

> The free ngrok plan allows **one agent session**. `just deploy` refuses to
> run while a host `ngrok` process is alive when ngrok is enabled.

## Cloudflare migration with ngrok retained

In `deploy/.env`, keep the current `NGROK_DOMAIN` and `NGROK_AUTHTOKEN` and add:

```dotenv
PUBLIC_TUNNELS=both
CLOUDFLARE_DOMAIN=garbanzo.fyi
CLOUDFLARE_TUNNEL_TOKEN=...  # copy the full token, not the tunnel UUID
PUBLIC_APP_URL=https://<existing-ngrok-domain>
```

`PUBLIC_APP_URL` selects the URL baked into the next Android/desktop release and
release tag. Keep it on ngrok while testing Cloudflare. Both origins are allowed
by backend CORS when the new Compose configuration is applied. The Cloudflare
route must be public without a Cloudflare Access login challenge, because native
clients use the app's own bearer authentication.

From the repository root, run `just deploy-test`, then `just deploy-config-check`.
`just deploy-tunnel-up cloudflared` starts only the connector, leaving the
running backend and ngrok in place. Check `https://garbanzo.fyi/api/v1/health`.
To apply the dual-origin backend CORS setting, run `just deploy-tunnel-apply`:
it recreates the backend container with the current image and environment, and
can briefly interrupt active requests. Test login, a streamed chat response,
and a room WebSocket from the Cloudflare hostname. `just deploy-status` checks
both public origins. Once validated, set `PUBLIC_APP_URL=https://garbanzo.fyi`
for a later release. Existing apps baked with ngrok continue to work while
`PUBLIC_TUNNELS=both`. Remove ngrok only after those clients are no longer in use: change
`PUBLIC_TUNNELS=cloudflare`, then run `just deploy-tunnel-stop ngrok`.
`just deploy-restart` does not remove previously running connectors.

Cloudflare Tunnel carries HTTP and WebSockets. Talk Mode's WebRTC media still
needs a separate public TURN relay; switching the HTTP tunnel does not provide
TURN. Store any TURN credentials separately from the connector token.

## What runs

| Service  | Image                    | Notes                                             |
|----------|--------------------------|---------------------------------------------------|
| postgres | pgvector/pgvector:pg16   | no host port, healthchecked, `postgres_data` vol  |
| ollama   | ollama/ollama:latest     | no host port, healthchecked, `ollama_data` vol    |
| backend  | garbanzo-backend:latest  | 127.0.0.1:8001 for smoke tests; serves web + API  |
| read-aloud | garbanzo-read-aloud:latest | private Pocket int8 worker on port 8021; 6 GiB RAM limit and separate model caches |
| ngrok    | ngrok/ngrok:latest       | optional legacy route → backend:8000              |
| cloudflared | cloudflare/cloudflared:latest | optional Cloudflare route → backend:8000 |

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
just deploy-psql
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
