import logging
import logging.config
import warnings
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.session import init_db

# Structured logging configuration
logging.config.dictConfig(
    {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "standard": {
                "format": "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
                "datefmt": "%Y-%m-%d %H:%M:%S",
            },
        },
        "handlers": {
            "console": {
                "class": "logging.StreamHandler",
                "formatter": "standard",
                "stream": "ext://sys.stdout",
            },
        },
        "root": {
            "level": "INFO",
            "handlers": ["console"],
        },
        "loggers": {
            "app": {"level": "DEBUG", "propagate": True},
            "uvicorn": {"level": "INFO", "propagate": False, "handlers": ["console"]},
            "sqlalchemy.engine": {"level": "WARNING", "propagate": False, "handlers": ["console"]},
        },
    }
)

logger = logging.getLogger(__name__)

# Get settings
settings = get_settings()

# Warn if SECRET_KEY is still the default
if settings.secret_key == "change-this-in-production":
    warnings.warn(
        "SECRET_KEY is set to the default value. "
        "Set a strong, unique SECRET_KEY in your .env file before deploying to production.",
        stacklevel=1,
    )


async def _ensure_test_user() -> None:
    """Create the test user if TEST_USER_EMAIL and TEST_USER_PASSWORD are set."""
    if not settings.test_user_email or not settings.test_user_password:
        return

    from app.core.security import hash_password
    from app.db.session import async_session_maker
    from app.services.user_service import UserService

    async with async_session_maker() as db:
        svc = UserService(db)
        existing = await svc.get_by_email(settings.test_user_email)
        if existing:
            logger.info("Test user already exists: %s", settings.test_user_email)
            return
        await svc.create(
            email=settings.test_user_email,
            hashed_password=hash_password(settings.test_user_password),
            full_name="Test User",
        )
        await db.commit()
        logger.info("Created test user: %s", settings.test_user_email)


def _register_default_llm_provider() -> None:
    """Register the default (Ollama) LLM provider in the process-wide registry.

    Idempotent — safe to call even if a provider with the same name is
    already registered (e.g. re-registered during tests).
    """
    from app.services.llm_provider import ProviderRegistry
    from app.services.ollama_provider import OllamaProvider

    if "ollama" not in ProviderRegistry.list_providers():
        ProviderRegistry.register(OllamaProvider(base_url=settings.ollama_base_url))


async def _promote_admin_emails() -> None:
    """Promote users matching settings.admin_emails_list to is_admin=True."""
    emails = settings.admin_emails_list
    if not emails:
        return

    from app.db.session import async_session_maker
    from app.services.user_service import UserService

    try:
        async with async_session_maker() as db:
            svc = UserService(db)
            for email in emails:
                user = await svc.get_by_email(email)
                if user is None:
                    logger.info("Admin email %s has no matching user yet", email)
                    continue
                if not user.is_admin:
                    user.is_admin = True
                    logger.info("Promoted %s to admin", email)
            await db.commit()
    except Exception:
        logger.warning("Failed to promote admin emails", exc_info=True)


async def _fail_stale_workflow_runs() -> None:
    """Mark workflow runs orphaned by a restart as failed.

    Their opencode subprocess died with the previous process, so a row left in
    ``queued``/``running`` can never advance — a polling client would wait on
    it forever.
    """
    from app.db.session import async_session_maker
    from app.services.workflow_service import WorkflowService

    try:
        async with async_session_maker() as db:
            swept = await WorkflowService(db).sweep_stale()
            if swept:
                logger.info("Failed %s workflow run(s) orphaned by restart", swept)
    except Exception:
        logger.warning("Could not sweep stale workflow runs", exc_info=True)


def _check_config() -> None:
    """Validate settings and log the feature table; refuse to boot on fatal issues."""
    from app.core.config import feature_summary, validate_startup_config

    fatal, warns = validate_startup_config(settings)
    for line in feature_summary(settings):
        logger.info("config | %s", line)
    for msg in warns:
        logger.warning("config | %s", msg)
    if fatal:
        for msg in fatal:
            logger.critical("config | %s", msg)
        raise RuntimeError("Refusing to start with invalid production config: " + "; ".join(fatal))


@asynccontextmanager
async def lifespan(app: FastAPI):
    _check_config()
    await init_db()
    _register_default_llm_provider()
    await _ensure_test_user()
    await _promote_admin_emails()
    from app.services.system_prompt_service import seed_builtin_templates_task

    await seed_builtin_templates_task()
    from app.services.style_service import seed_builtin_styles_task

    await seed_builtin_styles_task()
    await _fail_stale_workflow_runs()
    # Start loading the Kokoro TTS model in the background (non-blocking).
    from app.services.tts_service import TTSService

    TTSService.start_loading()

    # Start loading the Faster-Whisper STT model in the background (non-blocking).
    from app.services.stt_service import STTService

    STTService.start_loading()
    # Start the APScheduler for background jobs
    from app.scheduler import start_scheduler

    start_scheduler()

    # Initialize Firebase Admin SDK for push notifications (no-op if creds missing).
    from app.services.fcm_service import init_firebase

    init_firebase()
    yield
    # Shutdown scheduler on app exit
    from app.scheduler import stop_scheduler

    stop_scheduler()

    # Stop any running micro-apps workspaces (dev server + opencode subprocesses).
    from app.services.microapp_workspace import manager as microapp_manager

    microapp_manager.stop_all()


# Create FastAPI app
app = FastAPI(
    title=settings.app_name,
    description="FastAPI backend serving Garbanzo AI Flutter web app",
    version=settings.app_version,
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

# Micro-apps dev-server reverse proxy (no-op 404s unless MICROAPPS_PROXY_MODE
# is on). Must be registered before the SPA catch-all so /micro-apps/* wins.
from app.api import microapps_proxy  # noqa: E402

app.include_router(microapps_proxy.router)

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
        return HTMLResponse(
            content="""<!DOCTYPE html>
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
        <li><code>POST /api/v1/auth/login</code> - Login and get JWT token</li>
        <li><code>GET /api/v1/auth/me</code> - Get current user (requires auth)</li>
        <li><code>GET /docs</code> - API documentation (Swagger UI)</li>
    </ul>
    <h2>To build the Flutter web app:</h2>
    <pre><code>flutter build web --output ../backend/web</code></pre>
</body>
</html>"""
        )
