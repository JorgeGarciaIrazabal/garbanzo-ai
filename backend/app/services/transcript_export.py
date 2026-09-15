"""Shared transcript export surface for conversations and rooms.

Both export endpoints (``GET /chat/conversations/{id}/export`` and
``GET /rooms/{id}/export``) build the same thing: an ordered list of
:class:`docx_export.TranscriptSection` turns, rendered either as markdown or as
a Word document. Keeping the section builders here means the two resources
cannot drift apart in what "the transcript" contains.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from datetime import UTC, datetime
from typing import Any

from app.services.docx_export import (
    TranscriptSection,
    export_filename,
    format_extension,
    render_transcript_docx,
    slugify,
)

DOCX_MEDIA_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

__all__ = [
    "DOCX_MEDIA_TYPE",
    "TranscriptSection",
    "build_export_footer",
    "conversation_sections",
    "export_filename",
    "format_extension",
    "render_transcript_docx",
    "render_transcript_markdown",
    "room_sections",
    "slugify",
    "transcript_footer",
]

# Roles that are conversation machinery rather than transcript content. They
# are rendered as collapsible groups in the app UI, so the document exporter
# leaves them out and says so (see transcript_footer) instead of dumping raw
# tool JSON into the middle of a reader's document.
MACHINERY_ROLES = frozenset({"tool_call", "tool_result"})

_MARKDOWN_SEPARATOR = "---"


def _timestamp(value: datetime | None) -> str:
    if value is None:
        return ""
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone().strftime("%Y-%m-%d %H:%M")


def _audio_note_line(meta: dict[str, Any] | None) -> str | None:
    note = (meta or {}).get("audio_note")
    if not note:
        return None
    seconds = round(float(note.get("duration_seconds", 0)))
    return f"Audio note ({seconds // 60}:{seconds % 60:02d})"


def conversation_sections(
    messages: Sequence[Any], *, user_label: str
) -> tuple[list[TranscriptSection], int]:
    """Turn a conversation's messages into sections.

    Returns the sections plus the number of machinery messages left out so the
    caller can disclose the omission in the footer.
    """
    labels = {"user": user_label, "assistant": "Assistant", "system": "System"}
    sections: list[TranscriptSection] = []
    omitted = 0
    for message in messages:
        role = str(getattr(message, "role", "") or "")
        if role in MACHINERY_ROLES:
            omitted += 1
            continue
        content = getattr(message, "content", "") or ""
        if not content.strip():
            continue
        sections.append(
            TranscriptSection(
                author=labels.get(role, role or "Message"),
                body=content,
                meta=_timestamp(getattr(message, "created_at", None)),
            )
        )
    return sections, omitted


def room_sections(
    messages: Sequence[Any], agent_names: dict[str, str]
) -> tuple[list[TranscriptSection], int]:
    """Turn a room's messages into sections, resolving human and agent names."""
    sections: list[TranscriptSection] = []
    omitted = 0
    for message in messages:
        role = str(getattr(message, "role", "") or "")
        if role in MACHINERY_ROLES:
            omitted += 1
            continue
        content = getattr(message, "content", "") or ""
        sender_user_id = getattr(message, "sender_user_id", None)
        sender_agent_id = getattr(message, "sender_agent_id", None)
        if sender_user_id:
            author = str(sender_user_id)
        elif sender_agent_id:
            author = f"🤖 {agent_names.get(str(sender_agent_id), 'agent')}"
        else:
            author = role or "Message"
        audio_note = _audio_note_line(getattr(message, "meta", None))
        body = f"*{audio_note}*\n\n{content}" if audio_note else content
        if not body.strip():
            continue
        sections.append(
            TranscriptSection(
                author=author,
                body=body,
                meta=_timestamp(getattr(message, "created_at", None)),
            )
        )
    return sections, omitted


def transcript_footer(*, exported_at: datetime | None = None) -> str:
    """Closing note naming the source, so a saved file is self-describing."""
    stamp = (exported_at or datetime.now().astimezone()).strftime("%Y-%m-%d %H:%M %Z").strip()
    return f"Exported from Garbanzo AI · {stamp}"


def _footer_with_omissions(base: str, omitted: int) -> str:
    if not omitted:
        return base
    noun = "message" if omitted == 1 else "messages"
    return f"{base} · {omitted} tool {noun} omitted"


def render_transcript_markdown(
    *,
    title: str,
    sections: Iterable[TranscriptSection],
    subtitle: str | None = None,
    footer: str | None = None,
) -> str:
    """Markdown export: a heading per turn, the body verbatim."""
    lines: list[str] = [f"# {title}", ""]
    if subtitle:
        lines.extend([subtitle, ""])
    for section in sections:
        lines.append(f"## {section.author}")
        lines.append("")
        if section.meta:
            lines.extend([f"*{section.meta}*", ""])
        lines.extend([section.body, "", _MARKDOWN_SEPARATOR, ""])
    if footer:
        lines.extend([f"*{footer}*", ""])
    return "\n".join(lines)


def build_export_footer(base: str | None, omitted: int) -> str:
    """The footer used by the document exporters (discloses omissions)."""
    return _footer_with_omissions(base or transcript_footer(), omitted)
