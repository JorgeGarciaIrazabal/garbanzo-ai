# Garbanzo AI Backend

FastAPI backend that serves the Flutter web app and provides authentication APIs.

## Features

- **FastAPI** - Modern, fast Python web framework
- **JWT Authentication** - Secure token-based auth with bcrypt password hashing
- **CORS Support** - Configured for Flutter web development
- **Static File Serving** - Serves the Flutter web build as a SPA with fallback
- **uv** - Modern Python package manager (replaces pip + virtualenv)

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI app factory, CORS, static files
│   ├── core/
│   │   ├── config.py        # Pydantic settings from .env
│   │   └── security.py      # JWT and password hashing
│   ├── api/v1/
│   │   ├── router.py        # API router combining all endpoints
│   │   └── endpoints/
│   │       ├── auth.py      # Login, register, /me endpoints
│   │       └── health.py    # Health check endpoint
│   └── schemas/
│       ├── auth.py          # Token and login schemas
│       └── user.py          # User schemas
├── web/                     # Flutter web build output (gitignored)
├── pyproject.toml           # uv project config and dependencies
└── .env                     # Environment variables (not in git)
```

## Setup

1. Install uv if not already installed:
   ```powershell
   pip install uv
   ```

2. Copy the environment file (in PowerShell):
   ```powershell
   Copy-Item .env.example .env
   ```

3. Install dependencies:
   ```powershell
   uv sync
   ```

## Running the Server

### Development (with hot reload)
```powershell
uv run uvicorn app.main:app --reload
```

### Production
```powershell
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## API Endpoints

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET | `/api/v1/health` | Health check | No |
| POST | `/api/v1/auth/register` | Register new user | No |
| POST | `/api/v1/auth/login` | Login, returns JWT | No |
| GET | `/api/v1/auth/me` | Get current user | Yes |
| GET | `/docs` | Swagger UI docs | No |

## Authentication

The API uses JWT Bearer tokens:

1. Register a user (PowerShell):
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:8000/api/v1/auth/register" -Method POST -ContentType "application/json" -Body '{"username":"test","password":"password123","full_name":"Test User"}'
   ```

2. Login to get a token:
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:8000/api/v1/auth/login" -Method POST -ContentType "application/json" -Body '{"username":"test","password":"password123"}'
   ```

3. Use the token on protected endpoints:
   ```powershell
   Invoke-RestMethod -Uri "http://localhost:8000/api/v1/auth/me" -Headers @{ "Authorization" = "Bearer <your_token>" }
   ```

## Integration with Flutter

The backend serves the Flutter web app from the `web/` directory:

1. Build the Flutter web app (from the repo root):
   ```powershell
   just fe-build
   ```
   Or manually:
   ```powershell
   cd garbanzo_ai && flutter build web --output ../backend/web
   ```

2. The web build is output to `backend/web/`

3. Access the app at `http://localhost:8000/`

## Configuration

Edit `.env` to customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_NAME` | Application name | "Garbanzo AI" |
| `DEBUG` | Debug mode | `true` |
| `HOST` | Server host | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `SECRET_KEY` | JWT signing key | (required) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token expiration | `30` |
| `CORS_ORIGINS` | Allowed origins | comma-separated URLs |

## Development Commands

### Using `just` (recommended)

We use [just](https://github.com/casey/just) as a cross-platform command runner. Install it first:
- **Windows**: `winget install Casey.Just` or download from [releases](https://github.com/casey/just/releases)
- **macOS**: `brew install just`
- **Linux**: `curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash`

Then from the **repo root**:

```powershell
# Install everything
just install

# Run backend dev server
just be-dev

# Run Flutter on Chrome
just fe-run

# Build Flutter web into backend
just fe-build

# See all commands
just --list
```

### Manual commands

If you prefer, run commands directly from the `backend` directory:

```powershell
# Install dependencies
uv sync

# Run dev server
uv run uvicorn app.main:app --reload

# Run linter (ruff)
uv run ruff check .

# Run formatter (ruff)
uv run ruff format .

# Run tests (pytest)
uv run pytest
```

## Full Workflow Example

Open two PowerShell windows from the **repo root**:

**Terminal 1 - Backend:**
```powershell
just be-install  # First time only
just be-dev      # Start FastAPI server
```

**Terminal 2 - Flutter:**
```powershell
just fe-install  # First time only
just fe-run      # Run Flutter on Chrome
```

Or run commands manually without `just` — see "Manual commands" section above.

## Notes

- User data is stored in-memory (for development). Replace with a real database for production.
- Change the `SECRET_KEY` in production!
- The Flutter web build (`web/` directory) is gitignored.
