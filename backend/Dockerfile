FROM python:3.12-slim

# System deps for PyAV (ffmpeg), soundfile, and kokoro TTS (espeak-ng)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        libsndfile1 \
        espeak-ng \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Install dependencies in a cached layer (re-runs only when pyproject.toml/uv.lock change)
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen

# Copy application code — frozen snapshot of the codebase at build time
COPY app/ ./app/

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
