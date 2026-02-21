# Garbanzo AI - Just commands
# https://github.com/casey/just

# Use PowerShell on Windows
set shell := ["powershell.exe", "-c"]

# Default recipe - show help
_default:
    @just --list

# ============================================================================
# Setup & Combined Commands
# ============================================================================

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
    cd backend; uv sync

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

# Run Flutter app on Chrome (launches Chrome automatically, blocks terminal)
# Good for manual development, NOT for automated testing
fe-run:
    flutter run -d chrome

# Run Flutter web server on fixed port WITHOUT launching browser
# Use this for end-to-end testing with browser MCP
# The app will be available at http://localhost:8080
fe-run-test-server:
    flutter run -d web-server --web-port=8080 --web-hostname=localhost

# Build Flutter web and copy to backend
fe-build:
    flutter build web --output backend/web

# Run Flutter widget/unit tests
fe-test:
    flutter test

# Run Flutter integration tests (requires Chrome and running backend)
# This runs full E2E tests including user registration and login
fe-integration-test:
    flutter test integration_test/app_test.dart -d chrome

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

# Show instructions for running end-to-end tests
fe-e2e-test:
    @Write-Host ""
    @Write-Host "=== End-to-End Testing Options ===" -ForegroundColor Cyan
    @Write-Host ""
    @Write-Host "Option 1: Integration Tests (Recommended)" -ForegroundColor Green
    @Write-Host "  Run full E2E tests with:"
    @Write-Host "    1. just be-dev (start backend)"
    @Write-Host "    2. just fe-integration-test (runs E2E tests in Chrome)"
    @Write-Host ""
    @Write-Host "Option 2: Manual Testing with MCPs" -ForegroundColor Yellow
    @Write-Host "  Step 1: Start the backend:"
    @Write-Host "      just be-dev"
    @Write-Host ""
    @Write-Host "  Step 2: Start the Flutter test server:"
    @Write-Host "      just fe-run-test-server"
    @Write-Host "      (App will be at http://localhost:8080)"
    @Write-Host ""
    @Write-Host "  Step 3: Use the dart-mcp-server to connect:"
    @Write-Host "      - list_running_apps"
    @Write-Host "      - get_app_logs"
    @Write-Host ""
    @Write-Host "  Step 4: Use the browser MCP to interact:"
    @Write-Host "      - browser_navigate to http://localhost:8080"
    @Write-Host "      - browser_click, browser_type for user actions"
    @Write-Host "      - browser_snapshot for assertions"
    @Write-Host ""
    @Write-Host "Note: For best E2E testing results, use integration tests (Option 1)"
    @Write-Host "      as they have full access to Flutter widget tree."
    @Write-Host ""

# Run all tests (backend + frontend unit tests + e2e info)
test: be-test fe-test fe-e2e-test

# ============================================================================
# Full Build & Deploy
# ============================================================================

# Build everything (backend deps + Flutter web build)
build: be-install fe-build
    @Write-Host "Build complete! The web app is in backend/web/"

# Clean everything
clean: fe-clean
    @Write-Host "Cleaned Flutter build files"
