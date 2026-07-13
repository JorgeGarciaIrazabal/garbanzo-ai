"""Tests for image_utils.downscale_image_b64."""

import base64
import io

import pytest
from PIL import Image

from app.services.image_utils import downscale_image_b64


def _make_image_b64(width: int, height: int, mode: str = "RGB", fmt: str = "PNG") -> str:
    img = Image.new(mode, (width, height), (200, 100, 50) if mode == "RGB" else None)
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    return base64.b64encode(buf.getvalue()).decode("ascii")


def _decode(b64: str) -> Image.Image:
    return Image.open(io.BytesIO(base64.b64decode(b64)))


@pytest.mark.asyncio
async def test_large_image_downscaled_to_max_dim():
    original = _make_image_b64(3000, 1500)
    result = await downscale_image_b64(original, max_dim=1024)

    img = _decode(result)
    assert max(img.size) == 1024
    assert img.format == "JPEG"
    # Aspect ratio preserved
    assert img.size == (1024, 512)


@pytest.mark.asyncio
async def test_small_image_untouched():
    original = _make_image_b64(800, 600)
    result = await downscale_image_b64(original, max_dim=1024)
    assert result == original


@pytest.mark.asyncio
async def test_alpha_flattened_for_jpeg():
    original = _make_image_b64(2000, 2000, mode="RGBA")
    result = await downscale_image_b64(original, max_dim=1024)

    img = _decode(result)
    assert img.format == "JPEG"
    assert img.mode == "RGB"


@pytest.mark.asyncio
async def test_invalid_data_returns_original():
    garbage = base64.b64encode(b"not an image").decode("ascii")
    result = await downscale_image_b64(garbage, max_dim=1024)
    assert result == garbage
