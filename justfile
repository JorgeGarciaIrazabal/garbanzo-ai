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

# Enforce no in-function imports (Pylint C0415) — the one rule ruff lacks.
# Baseline of pre-existing offenders is in `.pylint-allowlist` so the check
# is green today and fails only on *new* files that add in-function imports.
be-lint-imports:
    #!/usr/bin/env bash
    cd backend
    # Build the list of files to lint: all .py under app/ and tests/,
    # minus the allowlist.
    allow_re="^($(paste -sd'|' .pylint-allowlist | sed 's/\./\\./g'))$"
    files=""
    while IFS= read -r f; do
        case "$f" in ""|\#*) continue ;; esac
        files="$files $f"
    done < <(find app tests -name '*.py' -not -path '*/.venv/*' | sort)
    # Filter out allowlisted files.
    lint_files=""
    for f in $files; do
        if ! grep -qx "$f" .pylint-allowlist; then
            lint_files="$lint_files $f"
        fi
    done
    if [ -z "$lint_files" ]; then
        echo "No files to lint (everything allowlisted)."
        exit 0
    fi
    uv run pylint --rcfile=.pylintrc $lint_files || exit $?

# Run ruff formatter on backend
be-format:
    cd backend; uv run ruff format .

# Run all backend tests, or pass pytest paths/options for a focused run
be-test *args:
    cd backend; uv run pytest {{args}}

# Run backend tests with coverage; accepts optional pytest paths/options
be-test-cov *args:
    cd backend; uv run pytest --cov=app --cov-report=xml --cov-report=term-missing {{args}}

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

# Build a debug Android APK without starting an emulator or backend
fe-build-apk:
    flutter build apk --debug

# Build a locally signed release APK without deploying it
fe-build-apk-release:
    #!/usr/bin/env bash
    set -euo pipefail
    set -a
    source "{{ justfile_directory() }}/deploy/.env"
    set +a
    flutter build apk --release

# Run all Flutter widget/unit tests, or pass test paths/options for a focused run
# Concurrency is capped: on a 32-core box `flutter test` defaults to 32 parallel
# processes, which stampedes memory (each spawns a full engine test binding) and
# froze the machine. 4 is fast enough for the suite (~10s) and safe.
fe-test *args:
    flutter test --concurrency=4 {{args}}

# Run Flutter tests with coverage; accepts optional test paths/options
fe-test-cov *args:
    flutter test --concurrency=4 --coverage {{args}}

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
check: be-format fe-format be-lint be-lint-imports fe-lint
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

# Create the permanent local Android release keystore and configure deploy/.env
deploy-android-signing-setup:
    "{{ justfile_directory() }}/scripts/setup-android-signing.sh"

# Pull one model into the isolated production Ollama volume
deploy-model model:
    {{ prod_compose }} exec ollama ollama pull "{{ model }}"

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
claude-ollama model="qwen3.8:27b":
    ollama launch claude --model {{model}} 

# Codex-first development (all commands accept --json)
[positional-arguments]
ai *args:
    @python3 -m scripts.ai_dev guided "$@"

[positional-arguments]
ai-setup *args:
    @python3 -m scripts.ai_dev setup "$@"

[positional-arguments]
ai-doctor *args:
    @python3 -m scripts.ai_dev doctor "$@"

[positional-arguments]
ai-models *args:
    @python3 -m scripts.ai_dev models "$@"

[positional-arguments]
ai-task *args:
    @python3 -m scripts.ai_dev task "$@"

[positional-arguments]
ai-run *args:
    @python3 -m scripts.ai_dev run "$@"

[positional-arguments]
ai-batch *args:
    @python3 -m scripts.ai_dev batch "$@"

[positional-arguments]
ai-status *args:
    @python3 -m scripts.ai_dev status "$@"

[positional-arguments]
ai-stop *args:
    @python3 -m scripts.ai_dev stop "$@"

[positional-arguments]
ai-resume *args:
    @python3 -m scripts.ai_dev resume "$@"

[positional-arguments]
ai-triage *args:
    @python3 -m scripts.ai_dev triage "$@"

[positional-arguments]
ai-reports *args:
    @python3 -m scripts.ai_dev reports "$@"

[positional-arguments]
ai-incident *args:
    @python3 -m scripts.ai_dev incident "$@"

[positional-arguments]
ai-search *args:
    @python3 -m scripts.ai_dev search "$@"

[positional-arguments]
ai-knowledge-refresh *args:
    @python3 -m scripts.ai_dev knowledge-refresh "$@"

[positional-arguments]
ai-preview *args:
    @python3 -m scripts.ai_dev preview "$@"

[positional-arguments]
ai-capacity *args:
    @python3 -m scripts.ai_dev capacity "$@"

[positional-arguments]
ai-nightly *args:
    @python3 -m scripts.ai_dev nightly "$@"

# Controller regression tests: no application services or provider allowance required
[positional-arguments]
ai-test *args:
    python3 -m unittest discover -s scripts/ai_dev/tests -v "$@"

ai-lint:
    cd backend; uv run ruff check ../scripts/ai_dev
    cd backend; uv run ruff format --check ../scripts/ai_dev

ai-format:
    cd backend; uv run ruff check --fix ../scripts/ai_dev
    cd backend; uv run ruff format ../scripts/ai_dev

# Production helper transport; SQL is passed on stdin by the bounded adapter
ai-prod-sql:
    @{{prod_compose}} exec -T postgres psql -X -q -A -t -v ON_ERROR_STOP=1 -U garbanzo -d garbanzo_ai_prod

ai-prod-services:
    @{{prod_compose}} ps --format json

ai-prod-logs:
    @{{prod_compose}} logs --no-color --tail=100 backend

# Serena uses the pinned revision and the repository's real Flutter SDK
ai-serena:
    @python3 -m scripts.ai_dev serena

# Internal pinned Serena runtime; launcher selects revision from .ai/toolchain.json
ai-serena-runtime revision:
    uv run --with "git+https://github.com/oraios/serena@{{revision}}" python scripts/ai_dev/serena_runtime.py start-mcp-server --project . --context codex --enable-web-dashboard false

# Read-only production readiness collection for development-session startup
ai-startup:
    @python3 -m scripts.ai_dev guided --inspect --json

ai-qmd-mcp:
    @PATH="{{justfile_directory()}}/.ai/tools/node_modules/.bin:$PATH" QMD_FORCE_CPU=1 qmd mcp

# Release preparation; called by explicit deploy, never by overnight work
[positional-arguments]
ai-changelog *args:
    @python3 -m scripts.ai_dev changelog "$@"

[positional-arguments]
ai-deployment-evidence *args:
    @python3 -m scripts.ai_dev deployment-evidence "$@"

# Real migrations in a disposable Docker-only PostgreSQL database
ai-migration-smoke:
    cd backend; PYTHONPATH=. uv run python ../scripts/ai_dev/migration_smoke.py --root ..

ai-navigation-smoke:
    cd backend; uv run python ../scripts/ai_dev/navigation_smoke.py

# Pinned private Ollama allowance reader; authentication stays in its own local store
ai-install-usage revision:
    UV_TOOL_DIR="{{justfile_directory()}}/.ai/tools/uv-tools" UV_TOOL_BIN_DIR="{{justfile_directory()}}/.ai/tools/bin" uv tool install --force "git+https://github.com/ontech7/ollama-usage@{{revision}}"

# Verified local secret scanner; version/checksum come from .ai/toolchain.json
ai-install-gitleaks version checksum:
    #!/usr/bin/env bash
    set -euo pipefail
    archive=$(mktemp)
    trap 'rm -f "$archive"' EXIT
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v{{version}}/gitleaks_{{version}}_linux_x64.tar.gz" -o "$archive"
    printf '%s  %s\n' "{{checksum}}" "$archive" | sha256sum -c -
    mkdir -p "{{justfile_directory()}}/.ai/tools/bin"
    tar -xzf "$archive" -C "{{justfile_directory()}}/.ai/tools/bin" gitleaks

ai-pip-audit:
    #!/usr/bin/env bash
    # pip-audit exit 1 means findings were produced; the controller triages them.
    set +e
    cd backend
    uv run --with pip-audit pip-audit --format json
    status=$?
    if [[ $status -ne 0 && $status -ne 1 ]]; then
        exit "$status"
    fi

ai-pip-audit-strict:
    cd backend; uv run --with pip-audit pip-audit --format json

ai-dart-audit:
    dart pub outdated --json

# Dependency and secret findings are sanitized into Beads by stable IDs
ai-audit:
    @python3 -m scripts.ai_dev audit

# Read the source revision label of the actual running production backend image
ai-prod-revision:
    @{{prod_compose}} ps -q backend | xargs -r docker inspect --format='{{'{{'}}index .Config.Labels "org.opencontainers.image.revision"{{'}}'}}'

# Report-bound read-only assertions against the actual deployed HTTP service
[positional-arguments]
ai-prod-behavior *args:
    @python3 -m scripts.ai_dev.behavior "$@"

[positional-arguments]
ai-nightly-worker *args:
    @python3 -m scripts.ai_dev nightly-worker "$@"
