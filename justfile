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

# Start PostgreSQL for local development (run before be-dev)
docker-up:
    docker compose up -d
    @Write-Host "PostgreSQL is running. Use 'just be-dev' to start the backend."

# ============================================================================
# Backend Commands (FastAPI)
# ============================================================================

# Install backend dependencies (uses uv)
be-install:
    cd backend; uv sync --extra dev

# Upgrade backend dependencies (uses uv)
be-upgrade:
    cd backend; uv sync --upgrade --extra dev

# Start FastAPI dev server with hot reload
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

# ============================================================================
# Full Build & Deploy
# ============================================================================

# Build everything (backend deps + Flutter web build)
build: be-install fe-build
    @Write-Host "Build complete! The web app is in backend/web/"

# Clean everything
clean: fe-clean
    @Write-Host "Cleaned Flutter build files"


# ============================================================================
# Claude code start up Commands
# ============================================================================
# Launch Claude Code with auto-approved permissions
claude:
    claude --dangerously-skip-permissions

# Launch Claude Code with a specific model
claude-ollama model="minimax-m2.7:cloud":
    ollama launch claude --model {{model}} 