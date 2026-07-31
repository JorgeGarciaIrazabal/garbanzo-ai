"""Image helpers for multimodal attachments."""

import asyncio
import base64
import io
import logging

from PIL import Image, ImageSequence

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Re-encode quality for downscaled JPEGs. 85 is visually lossless for photos
# and screenshots at the sizes vision models actually consume.
_JPEG_QUALITY = 85


def _flatten_for_jpeg(img: Image.Image) -> Image.Image:
    if img.mode in ("RGBA", "LA", "P"):
        rgba = img.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.split()[-1])
        return background
    return img if img.mode == "RGB" else img.convert("RGB")


def _downscale_sync(data_b64: str, max_dim: int, mime_type: str | None) -> str:
    raw = base64.b64decode(data_b64)
    with Image.open(io.BytesIO(raw)) as img:
        if max(img.size) <= max_dim:
            return data_b64

        output_format = {
            "image/png": "PNG",
            "image/gif": "GIF",
            "image/webp": "WEBP",
            "image/bmp": "BMP",
        }.get(mime_type, "JPEG")

        if output_format == "GIF" and getattr(img, "n_frames", 1) > 1:
            frames: list[Image.Image] = []
            durations: list[int] = []
            for frame in ImageSequence.Iterator(img):
                resized = frame.convert("RGBA")
                resized.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
                frames.append(resized)
                durations.append(frame.info.get("duration", img.info.get("duration", 100)))
            buf = io.BytesIO()
            frames[0].save(
                buf,
                format="GIF",
                save_all=True,
                append_images=frames[1:],
                duration=durations,
                loop=img.info.get("loop", 0),
            )
            return base64.b64encode(buf.getvalue()).decode("ascii")

        img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        if output_format == "JPEG":
            _flatten_for_jpeg(img).save(buf, format="JPEG", quality=_JPEG_QUALITY)
        else:
            img.save(buf, format=output_format)
        return base64.b64encode(buf.getvalue()).decode("ascii")


async def downscale_image_b64(
    data_b64: str,
    max_dim: int | None = None,
    *,
    mime_type: str | None = None,
) -> str:
    """Downscale a base64 image to ``max_dim`` px on its longest side.

    Images already within the limit are returned untouched (no re-encode).
    Decoding failures fall back to the original data — a corrupt attachment
    should surface as a model error, not break the send path.
    """
    limit = max_dim or get_settings().llm_image_max_dim
    try:
        return await asyncio.to_thread(_downscale_sync, data_b64, limit, mime_type)
    except Exception:
        logger.warning("Failed to downscale image attachment; using original")
        return data_b64
