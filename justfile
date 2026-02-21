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

# ============================================================================
# Backend Commands (FastAPI)
# ============================================================================

# Install backend dependencies (uses uv)
be-install:
    cd backend; uv sync

# Start FastAPI dev server with hot reload
be-dev:
    cd backend; uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Start FastAPI production server
be-run:
    cd backend; uv run uvicorn app.main:app --host 0.0.0.0 --port 8000

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

# Run Flutter app on Chrome
fe-run:
    flutter run -d chrome

# Build Flutter web and copy to backend
fe-build:
    flutter build web --output backend/web

# Run Flutter tests
fe-test:
    flutter test

# Run Flutter analyze
fe-lint:
    flutter analyze

# Clean Flutter build files
fe-clean:
    flutter clean

# ============================================================================
# Full Build & Deploy
# ============================================================================

# Build everything (backend deps + Flutter web build)
build: be-install fe-build
    @Write-Host "Build complete! The web app is in backend/web/"

# Clean everything
clean: fe-clean
    @Write-Host "Cleaned Flutter build files"
