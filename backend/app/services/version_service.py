"""Latest-release lookup for the native auto-updaters.

Proxies the GitHub Releases API so clients don't hit GitHub's unauthenticated
rate limit (60 req/h per IP) directly; a short in-memory cache keeps repeated
update checks from re-fetching.
"""

import time

import httpx
from fastapi import HTTPException

from app.core.config import get_settings
from app.schemas.version import LatestVersionResponse, ReleaseAsset

CACHE_TTL_SECONDS = 300.0

_cache: tuple[float, LatestVersionResponse] | None = None


def clear_cache() -> None:
    global _cache
    _cache = None


def _parse_release(data: dict) -> LatestVersionResponse:
    tag = data.get("tag_name") or ""
    return LatestVersionResponse(
        version=tag.removeprefix("v"),
        tag_name=tag,
        name=data.get("name"),
        body=data.get("body"),
        published_at=data.get("published_at"),
        html_url=data.get("html_url") or "",
        assets=[
            ReleaseAsset(
                name=a.get("name") or "",
                download_url=a.get("browser_download_url") or "",
                size=a.get("size") or 0,
            )
            for a in data.get("assets", [])
        ],
    )


async def get_latest_release() -> LatestVersionResponse:
    global _cache
    if _cache is not None and time.monotonic() - _cache[0] < CACHE_TTL_SECONDS:
        return _cache[1]

    repo = get_settings().github_repo
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers={"Accept": "application/vnd.github+json"})
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail=f"GitHub unreachable: {exc}") from exc

    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail=f"No releases found for {repo}")
    if resp.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"GitHub returned {resp.status_code} for {repo}",
        )

    release = _parse_release(resp.json())
    _cache = (time.monotonic(), release)
    return release
