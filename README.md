# Garbanzo AI

A Flutter web app with FastAPI backend.

## Quick Start

### Prerequisites

1. **Flutter** - Install from [flutter.dev](https://flutter.dev)
2. **uv** - Install with `pip install uv`
3. **just** (optional but recommended) - Install with `winget install Casey.Just`

### Development

From the repo root:

```powershell
# Install all dependencies
just install

# Terminal 1: Start backend
just be-dev

# Terminal 2: Run Flutter app
just fe-run
```

Then open:
- `http://localhost:8000/docs` - API documentation
- `http://localhost:8000/` - Backend placeholder (or Flutter web after build)

### Available Commands

Run `just --list` to see all available commands:

| Command | Description |
|---------|-------------|
| `just install` | Install all dependencies (backend + frontend) |
| `just be-dev` | Start FastAPI dev server with hot reload |
| `just be-run` | Start FastAPI production server |
| `just be-lint` | Run ruff linter on backend |
| `just be-format` | Run ruff formatter on backend |
| `just be-test` | Run pytest on backend |
| `just fe-run` | Run Flutter app on Chrome |
| `just fe-build` | Build Flutter web into backend/web/ |
| `just fe-test` | Run Flutter tests |
| `just fe-lint` | Run Flutter analyze |

### Project Structure

```
garbanzo_ai/
├── justfile              # Command runner (Make alternative)
├── backend/              # FastAPI backend
│   ├── app/
│   │   ├── main.py       # FastAPI app
│   │   ├── api/v1/       # API routes
│   │   ├── core/         # Security, config
│   │   └── schemas/      # Pydantic models
│   ├── web/              # Flutter build output (gitignored)
│   └── pyproject.toml    # uv dependencies
│
└── garbanzo_ai/          # Flutter app
    ├── lib/
    └── pubspec.yaml
```

### Building for Production

Build the Flutter web app into the backend:

```powershell
just fe-build
```

Then start the backend — it will serve the Flutter app at the root URL.

## Notes

- See `backend/README.md` for detailed backend documentation
- Backend API uses JWT email/password authentication
- Passwords must be between 6 and 72 bytes (bcrypt limitation)

## Troubleshooting

If `just` command is not found after installing with winget, restart your terminal or run:
```powershell
$env:Path += ";$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Casey.Just_Microsoft.Winget.Source_8wekyb3d8bbwe"
```
