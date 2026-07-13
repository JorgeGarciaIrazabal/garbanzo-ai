"""Image helpers for multimodal attachments."""

import asyncio
import base64
import io
import logging

from PIL import Image

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Re-encode quality for downscaled JPEGs. 85 is visually lossless for photos
# and screenshots at the sizes vision models actually consume.
_JPEG_QUALITY = 85


def _downscale_sync(data_b64: str, max_dim: int) -> str:
    raw = base64.b64decode(data_b64)
    with Image.open(io.BytesIO(raw)) as img:
        if max(img.size) <= max_dim:
            return data_b64

        img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
        # JPEG can't carry alpha — flatten transparent images onto white.
        if img.mode in ("RGBA", "LA", "P"):
            img = img.convert("RGBA")
            background = Image.new("RGB", img.size, (255, 255, 255))
            background.paste(img, mask=img.split()[-1])
            img = background
        elif img.mode != "RGB":
            img = img.convert("RGB")

        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=_JPEG_QUALITY)
        return base64.b64encode(buf.getvalue()).decode("ascii")


async def downscale_image_b64(data_b64: str, max_dim: int | None = None) -> str:
    """Downscale a base64 image to ``max_dim`` px on its longest side.

    Images already within the limit are returned untouched (no re-encode).
    Decoding failures fall back to the original data — a corrupt attachment
    should surface as a model error, not break the send path.
    """
    limit = max_dim or get_settings().llm_image_max_dim
    try:
        return await asyncio.to_thread(_downscale_sync, data_b64, limit)
    except Exception:
        logger.warning("Failed to downscale image attachment; using original")
        return data_b64
