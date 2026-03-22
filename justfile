# Garbanzo AI - Just commands
# https://github.com/casey/just

# Default recipe - show help
_default:
    @just --list

# ============================================================================
# Setup & Combined Commands
# ============================================================================

# Add just bash completions to ~/.bashrc (run once)
completions-install:
    @SCRIPT="{{ justfile_directory() }}/scripts/just-completions.bash"; \
    LINE="source \"$SCRIPT\""; \
    grep -qF "$LINE" ~/.bashrc \
        && echo "Completions already installed in ~/.bashrc" \
        || { echo "$LINE" >> ~/.bashrc; echo "Added completions to ~/.bashrc — run 'source ~/.bashrc' to activate."; }

# Install all dependencies (backend + frontend)
install: be-install fe-install
    @Write-Host "All dependencies installed!"

# Install Linux system dependencies required for audio (GStreamer for audioplayers + record)
dev-deps:
    sudo apt-get install -y \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad

# Start Docker, backend, TTS, and frontend together — kills port 8000 if busy
dev:
    #!/usr/bin/env bash
    set -e
    if ! pkg-config --exists gstreamer-1.0 2>/dev/null; then
        echo "Error: GStreamer not found. Run 'just dev-deps' first to install audio dependencies."
        exit 1
    fi
    if lsof -ti:8000 > /dev/null 2>&1; then
        PIDS=$(lsof -ti:8000 | tr '\n' ' ')
        printf "Port 8000 is in use by PID(s) %s. Kill? [y/N] " "$PIDS"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            lsof -ti:8000 | xargs kill
            echo "Killed."
        else
            echo "Aborting."
            exit 1
        fi
    fi
    docker compose up -d
    echo "Starting backend on :8000 (includes in-process Kokoro TTS)..."
    (cd backend && uv run uvicorn app.main:app --reload --port 8000) &
    BACKEND_PID=$!
    trap "kill $BACKEND_PID 2>/dev/null; echo 'Stopped.'" EXIT INT TERM
    echo "Starting frontend..."
    flutter run -d linux

# Start all services (PostgreSQL, STT, TTS)
docker-up:
    docker compose up -d

# Start only PostgreSQL for local development
docker-up-db:
    docker compose up -d postgres

# Run all SQL migration files in backend/migrations/ against the dev database (idempotent)
db-migrate:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in "{{ justfile_directory() }}/backend/migrations/"*.sql; do
        echo "Applying $(basename $f)..."
        docker exec -i garbanzo_ai_postgres psql -U garbanzo -d garbanzo_ai < "$f"
    done
    echo "Done."

# ============================================================================
# Backend Commands (FastAPI)
# ============================================================================

# Install backend dependencies (uses uv)
be-install:
    cd backend; uv sync --extra dev

# Upgrade backend dependencies (uses uv)
be-upgrade:
    cd backend; uv sync --upgrade --extra dev

# Start FastAPI dev server with hot reload (includes in-process Kokoro TTS)
be-dev:
    cd backend; uv run uvicorn app.main:app --reload --port 8000

# Start FastAPI production server
be-run:
    cd backend; uv run uvicorn app.main:app --port 8000

# Run ruff linter on backend
be-lint:
    cd backend; uv run ruff check .

# Run ruff formatter on backend
be-format:
    cd backend; uv run ruff format .

# Run pytest on backend
be-test:
    cd backend; uv run pytest

# ============================================================================
# Frontend Commands (Flutter)
# ============================================================================

# Install frontend dependencies
fe-install:
    flutter pub get

# Run Flutter app on Linux desktop (default for development)
fe-run:
    flutter run -d linux

# Run Flutter app on Chrome
fe-run-chrome:
    flutter run -d chrome

# Run Flutter app on Linux desktop against an ngrok backend
# Usage: just fe-run-ngrok https://xxxx.ngrok-free.app
fe-run-ngrok url:
    flutter run -d linux --dart-define=API_BASE_URL={{url}}

# Build Flutter web and copy to backend
fe-build:
    flutter build web --output backend/web

# Run Flutter widget/unit tests
fe-test:
    flutter test

# Run Flutter integration tests on Linux desktop
fe-integration-test:
    flutter test integration_test/app_test.dart -d linux

# Run all tests (unit + integration)
fe-test-all: fe-test fe-integration-test

# Run Flutter analyze
fe-lint:
    flutter analyze

# Clean Flutter build files
fe-clean:
    flutter clean

# ============================================================================
# End-to-End Testing (requires both dart-mcp-server and chrome-devtools MCPs)
# ============================================================================

# Run all tests (backend + frontend unit tests)
test: be-test fe-test

# Run Flutter integration tests via a fixed-port web test server
fe-run-test-server:
    flutter run -d linux --dart-define=API_BASE_URL=http://localhost:8000

# ============================================================================
# Full Build & Deploy
# ============================================================================

# Build everything (backend deps + Flutter web build)
build: be-install fe-build
    @Write-Host "Build complete! The web app is in backend/web/"

# Clean everything
clean: fe-clean
    @Write-Host "Cleaned Flutter build files"

# Build backend Docker image + start all services + expose via ngrok + build Android APK
# Usage:
#   just android                              # use NGROK_DOMAIN from backend/.env
#   just android https://xyz.ngrok-free.app  # override with a different URL
android url="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Load NGROK_DOMAIN from backend/.env if present
    if [ -f "{{ justfile_directory() }}/backend/.env" ]; then
        export $(grep -E '^NGROK_DOMAIN=' "{{ justfile_directory() }}/backend/.env" | xargs)
    fi

    # 1. Start ngrok tunnel (static domain or auto-detect)
    if [ -n "{{url}}" ]; then
        API_URL="{{url}}"
    elif [ -n "${NGROK_DOMAIN:-}" ]; then
        API_URL="https://${NGROK_DOMAIN}"
        if ! curl -s http://localhost:4040/api/tunnels > /dev/null 2>&1; then
            echo "Starting ngrok tunnel → ${NGROK_DOMAIN}..."
            ngrok http --domain "${NGROK_DOMAIN}" 8001 > /dev/null &
            for i in $(seq 1 15); do
                sleep 1
                curl -s http://localhost:4040/api/tunnels > /dev/null 2>&1 && break
                [ $i -eq 15 ] && { echo "Error: ngrok did not start"; exit 1; }
            done
        fi
    else
        echo "Error: set NGROK_DOMAIN in backend/.env or pass a URL"; exit 1
    fi

    # 2. Build frozen backend Docker image from current code
    echo "Building backend Docker image (frozen snapshot)..."
    docker compose build backend

    # 3. Start all Docker services (postgres, whisper, backend)
    echo "Starting services..."
    docker compose up -d

    # 4. Build Android APK with the ngrok URL baked in
    echo "Building Android APK → API_BASE_URL=$API_URL"
    cd "{{ justfile_directory() }}" && flutter build apk --release --dart-define=API_BASE_URL="$API_URL"
    echo ""
    echo "APK: build/app/outputs/flutter-apk/app-release.apk"
    echo "Backend: $API_URL  (Docker-managed, edit code won't affect it until next build)"


# ============================================================================
# Claude code start up Commands
# ============================================================================
# Launch Claude Code with auto-approved permissions
claude:
    claude --dangerously-skip-permissions

# Launch Claude Code with a specific model
claude-ollama model="qwen3.5:397b-cloud":
    ollama launch claude --model {{model}} 
