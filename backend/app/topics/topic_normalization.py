"""Pure normalization helpers shared by topic services."""

from __future__ import annotations

import re


def normalize_topic_label(label: str) -> str:
    """Return a stable, human-language-independent topic dedupe key."""
    return " ".join(re.sub(r"[^\w\s-]", " ", label.casefold()).split())[:200]
