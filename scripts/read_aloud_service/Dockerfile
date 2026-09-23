FROM python:3.12-slim-bookworm
COPY --from=ghcr.io/astral-sh/uv:0.8.22 /uv /uvx /bin/
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /service
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY app.py ./
ENV PATH="/service/.venv/bin:$PATH" \
    HF_HOME=/models/huggingface \
    POCKET_TTS_CACHE_DIR=/models/pocket-tts \
    HF_HUB_DISABLE_XET=1 \
    OMP_NUM_THREADS=4
EXPOSE 8021
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8021", "--workers", "1"]
