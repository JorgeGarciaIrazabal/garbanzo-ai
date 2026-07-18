"""Reverse geocoding for the opt-in location.

One Nominatim lookup per explicit user action (enabling the settings toggle
or refreshing their location) — never per chat turn — which keeps us well
inside the public instance's 1 req/s usage policy. Coordinates are consumed
transiently; only the resolved place name (e.g. "Malasaña, Madrid, Spain")
leaves this module — precise coordinates are never persisted or logged.
"""

import logging

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Nominatim's usage policy requires an identifying User-Agent; the default
# python-httpx one gets throttled or blocked.
_USER_AGENT = "garbanzo-ai (self-hosted chat app)"

# zoom=14 asks for neighbourhood/suburb-level detail — precise enough to be
# useful for "restaurants near me" while still stopping short of the exact
# street or building the raw coordinates would pin down.
_ZOOM_NEIGHBOURHOOD = 14


async def reverse_geocode_place(latitude: float, longitude: float) -> str | None:
    """Resolve coordinates to a ``"Neighbourhood, City, Country"`` string.

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
                    "zoom": _ZOOM_NEIGHBOURHOOD,
                    "accept-language": "en",
                },
                headers={"User-Agent": _USER_AGENT},
            )
            resp.raise_for_status()
            data = resp.json()
    except Exception as e:
        logger.warning("Reverse geocode failed: %s", e)
        return None

    return format_place(data)


def format_place(data: dict) -> str | None:
    """Extract ``"Neighbourhood, City, Country"`` from a Nominatim response.

    Each tier degrades gracefully: a place with no distinct neighbourhood
    collapses to ``"City, Country"``, and a remote spot with only a country
    to just the country. Duplicate names (a district that shares its city's
    name) are folded so we never emit ``"Madrid, Madrid, Spain"``.
    """
    address = data.get("address") or {}
    # Nominatim names the sub-city area differently by region/size.
    area = next(
        (
            address[k]
            for k in ("neighbourhood", "suburb", "city_district", "quarter", "borough")
            if address.get(k)
        ),
        None,
    )
    # ...and the settlement itself differently by size.
    city = next(
        (
            address[k]
            for k in ("city", "town", "village", "municipality", "county")
            if address.get(k)
        ),
        None,
    )
    country = address.get("country")
    # dict.fromkeys preserves order while dropping repeats (e.g. area == city).
    parts = list(dict.fromkeys(p for p in (area, city, country) if p))
    return ", ".join(parts) or None
