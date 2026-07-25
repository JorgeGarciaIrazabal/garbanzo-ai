# Garbanzo AI - Just commands
# https://github.com/casey/just

prod_compose := "docker compose -f " + justfile_directory() + "/deploy/docker-compose.yml --env-file " + justfile_directory() + "/deploy/.env"

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
    @echo "All dependencies installed!"

# Install Linux system dependencies required for audio (GStreamer for audioplayers + record)
dev-deps:
    sudo apt-get install -y \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad


opencode:
	ollama launch opencode --model micro-apps-glm --yes


# Start Docker, backend, TTS, and frontend on Android (real device or emulator) — kills port 8000 if busy
dev-apk:
    #!/usr/bin/env bash
    set -e
    export ANDROID_HOME="$HOME/Android/Sdk"
    export PATH="$HOME/.local/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
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
    (cd backend && uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000) &
    BACKEND_PID=$!
    trap "kill $BACKEND_PID 2>/dev/null; echo 'Stopped.'" EXIT INT TERM
    # Check for a real USB-connected Android device first
    DEVICES_OUTPUT=$(flutter devices 2>/dev/null)
    REAL_DEVICE=$(echo "$DEVICES_OUTPUT" | grep "android" | grep -v "emulator" | head -1)
    if [ -n "$REAL_DEVICE" ]; then
        DEVICE_ID=$(echo "$REAL_DEVICE" | sed 's/.*• \([^ ]*\) • android.*/\1/')
        LOCAL_IP=$(ip route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
        API_URL="http://${LOCAL_IP}:8000"
        echo "Real device detected: $DEVICE_ID"
        echo "Using host IP: $API_URL"
    else
        # Fall back to emulator
        if ! echo "$DEVICES_OUTPUT" | grep -q "emulator"; then
            echo "No Android device found. Launching emulator..."
            flutter emulators --launch Medium_Phone_API_36.1
            echo "Waiting for emulator to boot..."
            adb wait-for-device
            while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
                sleep 2
            done
            echo "Emulator ready."
        fi
        DEVICE_ID=$(flutter devices 2>/dev/null | grep "emulator" | head -1 | sed 's/.*• \(emulator-[0-9]*\) .*/\1/')
        API_URL="http://10.0.2.2:8000"
        echo "Using emulator: $DEVICE_ID"
        echo "Using host alias: $API_URL"
    fi
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: Could not determine Android device ID."
        exit 1
    fi
    echo "Starting frontend..."
    flutter run -d "$DEVICE_ID" --dart-define=API_BASE_URL="$API_URL"

# Start Docker, backend, and frontend on Linux desktop — kills port 8000 if busy
dev:
    #!/usr/bin/env bash
    set -e
    export PATH="$HOME/.local/bin:$PATH"
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
    (cd backend && uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000) &
    BACKEND_PID=$!
    trap "kill $BACKEND_PID 2>/dev/null; echo 'Stopped.'" EXIT INT TERM
    echo "Starting frontend on Linux desktop..."
    flutter run -d linux --dart-define=API_BASE_URL=http://localhost:8000

# Start Docker, backend, and frontend in Chrome for web development — kills port 8000 if busy
dev-web:
    #!/usr/bin/env bash
    set -e
    export PATH="$HOME/.local/bin:$PATH"
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
    (cd backend && uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000) &
    BACKEND_PID=$!
    trap "kill $BACKEND_PID 2>/dev/null; echo 'Stopped.'" EXIT INT TERM
    echo "Starting frontend on Chrome..."
    flutter run -d chrome

# Start all services (PostgreSQL, STT, TTS)
docker-up:
    docker compose up -d

# Start only PostgreSQL for local development
docker-up-db:
    docker compose up -d postgres

# NOTE: SQL migrations in backend/migrations/ are applied automatically at
# backend startup (tracked in the schema_migrations table) — no manual step.

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

# Run pytest on backend with coverage (writes backend/coverage.xml)
be-test-cov:
    cd backend; uv run pytest --cov=app --cov-report=xml --cov-report=term-missing

# ============================================================================
# Frontend Commands (Flutter)
# ============================================================================

# Install frontend dependencies
fe-install:
    flutter pub get

# Upgrade frontend dependencies within their declared constraints
fe-upgrade:
    flutter pub upgrade

# Upgrade frontend dependencies and their declared constraints to current versions
fe-upgrade-major:
    flutter pub upgrade --major-versions

# Show frontend dependencies that require a constraint update
fe-outdated:
    flutter pub outdated

# Update the installed Flutter SDK before refreshing dependency constraints
fe-upgrade-sdk:
    flutter upgrade

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
    flutter build web --wasm --output backend/web

# Run Flutter widget/unit tests
# Concurrency is capped: on a 32-core box `flutter test` defaults to 32 parallel
# processes, which stampedes memory (each spawns a full engine test binding) and
# froze the machine. 4 is fast enough for the suite (~10s) and safe.
fe-test:
    flutter test --concurrency=4

# Run Flutter tests with coverage (writes coverage/lcov.info)
fe-test-cov:
    flutter test --concurrency=4 --coverage

# Format Dart files (lib/ only — mirrors pre-commit hook)
fe-format:
    dart format lib/

# Regenerate committed Flutter localization sources from the ARB files
fe-gen-l10n:
    flutter gen-l10n

# Run Flutter analyze
fe-lint: fe-gen-l10n
    flutter analyze

# Clean Flutter build files
fe-clean:
    flutter clean

# ============================================================================
# End-to-End Testing (requires both dart-mcp-server and chrome-devtools MCPs)
# ============================================================================

# Format + lint everything (run before committing to satisfy pre-commit hooks)
check: be-format fe-format be-lint fe-lint
    @echo "All checks passed — ready to commit."

# Run all tests (backend + frontend unit tests)
test: be-test fe-test

# Run Flutter integration tests via a fixed-port web test server
fe-run-test-server:
    flutter run -d linux --dart-define=API_BASE_URL=http://localhost:8000

# ============================================================================
# Deployment (prod stack under deploy/ — see deploy/README.md)
# ============================================================================

# Deploy local main: web build → backend image → prod stack → APK (+ install on Android if connected)
deploy:
    "{{ justfile_directory() }}/scripts/deploy.sh"

# Install the latest built APK from dist/ onto a connected Android device
deploy-apk-install:
    #!/usr/bin/env bash
    set -euo pipefail
    export ANDROID_HOME="$HOME/Android/Sdk"
    export PATH="$ANDROID_HOME/platform-tools:$PATH"
    APK=$(ls -t {{ justfile_directory() }}/dist/garbanzo-ai-*.apk 2>/dev/null | head -1)
    if [ -z "$APK" ]; then
        echo "No APK found in dist/. Run 'just deploy' first."
        exit 1
    fi
    echo "Installing: $APK"
    if ! adb get-state >/dev/null 2>&1; then
        echo "No Android device connected. Connect one (USB debugging enabled) or start an emulator."
        exit 1
    fi
    adb install -r "$APK"

# Show prod stack status + local & public health
deploy-status:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ prod_compose }} ps
    echo ""
    curl -fsS http://127.0.0.1:8001/api/v1/health >/dev/null 2>&1 \
        && echo "local  http://127.0.0.1:8001 — OK" \
        || echo "local  http://127.0.0.1:8001 — DOWN"
    DOMAIN=$(grep -E '^NGROK_DOMAIN=' "{{ justfile_directory() }}/deploy/.env" | cut -d= -f2)
    curl -fsS -H "ngrok-skip-browser-warning: 1" "https://${DOMAIN}/api/v1/health" >/dev/null 2>&1 \
        && echo "public https://${DOMAIN} — OK" \
        || echo "public https://${DOMAIN} — DOWN"

# Tail prod logs (optionally one service: backend | postgres | ngrok)
deploy-logs service="":
    {{ prod_compose }} logs -f --tail=200 {{ service }}

# Restart prod services (keeps data)
deploy-restart:
    {{ prod_compose }} restart

# Stop the prod stack (keeps volumes/data)
deploy-down:
    {{ prod_compose }} down


# Clean everything
clean: fe-clean
    @echo "Cleaned Flutter build files"


# ============================================================================
# Claude code start up Commands
# ============================================================================
# Launch Claude Code with auto-approved permissions
claude:
    claude --dangerously-skip-permissions

# Launch Claude Code with a specific model
claude-ollama model="qwen3.5:397b-cloud":
    ollama launch claude --model {{model}} 
