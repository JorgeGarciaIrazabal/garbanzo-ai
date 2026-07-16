"""Reverse geocoding for the opt-in coarse location.

One Nominatim lookup per explicit user action (enabling the settings toggle
or refreshing their location) — never per chat turn — which keeps us well
inside the public instance's 1 req/s usage policy. Coordinates are consumed
transiently; only the resolved "City, Country" string leaves this module.
"""

import logging

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Nominatim's usage policy requires an identifying User-Agent; the default
# python-httpx one gets throttled or blocked.
_USER_AGENT = "garbanzo-ai (self-hosted chat app)"

# zoom=10 asks for city-level detail, matching the coarsest useful answer —
# we never want street or neighbourhood precision.
_ZOOM_CITY = 10


async def reverse_geocode_city(latitude: float, longitude: float) -> str | None:
    """Resolve coordinates to a coarse ``"City, Country"`` string.

    Returns None when the lookup fails or resolves to nothing useful (open
    ocean, rate-limited, network down) — callers treat that as "couldn't
    resolve", never as an error that should surface coordinates.
    """
    settings = get_settings()
    url = f"{settings.nominatim_url.rstrip('/')}/reverse"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                url,
                params={
                    "lat": latitude,
                    "lon": longitude,
                    "format": "jsonv2",
                    "zoom": _ZOOM_CITY,
                    "accept-language": "en",
                },
                headers={"User-Agent": _USER_AGENT},
            )
            resp.raise_for_status()
            data = resp.json()
    except Exception as e:
        logger.warning("Reverse geocode failed: %s", e)
        return None

    return format_city(data)


def format_city(data: dict) -> str | None:
    """Extract ``"City, Country"`` from a Nominatim reverse response."""
    address = data.get("address") or {}
    # Nominatim names the settlement differently by size/region.
    city = next(
        (
            address[k]
            for k in ("city", "town", "village", "municipality", "county")
            if address.get(k)
        ),
        None,
    )
    country = address.get("country")
    parts = [p for p in (city, country) if p]
    return ", ".join(parts) or None
