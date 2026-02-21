import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.session import init_db

# Get settings
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


# Create FastAPI app
app = FastAPI(
    title=settings.app_name,
    description="FastAPI backend serving Garbanzo AI Flutter web app",
    version="0.1.0",
    debug=settings.debug,
    lifespan=lifespan,
)

# Configure CORS
# In debug mode, also allow Flutter dev server (random port, e.g. localhost:55596)
cors_origins = settings.cors_origins_list
if settings.debug:
    cors_origins = list(cors_origins) + [
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:5000",
    ]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?$" if settings.debug else None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API router
app.include_router(api_router, prefix="/api/v1")

# Determine web directory path
web_dir = Path(__file__).parent.parent / "web"


# Serve Flutter web app
if web_dir.exists() and (web_dir / "index.html").exists():
    # Mount static files
    app.mount("/assets", StaticFiles(directory=web_dir / "assets"), name="assets")

    @app.get("/", response_class=HTMLResponse)
    async def root() -> HTMLResponse:
        index_file = web_dir / "index.html"
        content = index_file.read_text(encoding="utf-8")
        return HTMLResponse(content=content)

    @app.get("/{path:path}", response_class=FileResponse)
    async def catch_all(path: str):
        # Try to serve the file if it exists
        file_path = web_dir / path
        if file_path.exists() and file_path.is_file():
            return FileResponse(file_path)

        # Otherwise, serve index.html for SPA routing
        index_file = web_dir / "index.html"
        content = index_file.read_text(encoding="utf-8")
        return HTMLResponse(content=content)
else:
    # Fallback when web build doesn't exist
    @app.get("/", response_class=HTMLResponse)
    async def root_placeholder() -> HTMLResponse:
        return HTMLResponse(content="""<!DOCTYPE html>
<html>
<head>
    <title>Garbanzo AI Backend</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #6366f1; }
        code { background: #f3f4f6; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>Garbanzo AI Backend</h1>
    <p>The backend is running, but the Flutter web app has not been built yet.</p>
    <h2>Available Endpoints:</h2>
    <ul>
        <li><code>GET /api/v1/health</code> - Health check</li>
        <li><code>POST /api/v1/auth/register</code> - Register a new user</li>
        <li><code>POST /api/v1/auth/login</code> - Login and get JWT token</li>
        <li><code>GET /api/v1/auth/me</code> - Get current user (requires auth)</li>
        <li><code>GET /docs</code> - API documentation (Swagger UI)</li>
    </ul>
    <h2>To build the Flutter web app:</h2>
    <pre><code>flutter build web --output ../backend/web</code></pre>
</body>
</html>""")
