FROM python:3.12-slim

# ffmpeg (PyAV), libsndfile1 (soundfile), espeak-ng (Kokoro TTS);
# git + openssh-client (micro-apps worktrees + publish over SSH);
# procps (pkill — subprocess cleanup belt for dev servers/opencode).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        libsndfile1 \
        espeak-ng \
        git \
        openssh-client \
        procps \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js + npm (micro-apps Vite dev servers) from the official image, plus
# the opencode agent CLI.
COPY --from=node:22-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:22-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && npm install -g opencode-ai \
    && npm cache clean --force

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1

# Install dependencies in a cached layer (re-runs only when the lockfile changes)
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --no-dev --frozen

# Application code + SQL migrations (applied automatically at startup)
COPY app/ ./app/
COPY migrations/ ./migrations/

# Flutter web build output. scripts/deploy.sh stages this into the build
# context; build the web app first if building the image by hand.
COPY web/ ./web/

# Release version baked in by scripts/deploy.sh (matches the git tag / the
# desktop builds from the same release). Reported by GET /api/v1/health.
ARG APP_VERSION=0.0.0-dev
ENV APP_VERSION=$APP_VERSION

# Run straight from the venv — no resolver at container start.
# Secrets and environment come from the compose file at runtime, never the image.
ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
