"""Shared request schema for muting notifications (rooms + conversations)."""

from typing import Literal

from pydantic import BaseModel

MuteDuration = Literal["8h", "1w", "forever", "unmute"]


class MuteUpdate(BaseModel):
    """Mute or unmute notifications for the current user.

    ``8h`` / ``1w`` set ``muted_until`` to now + duration, ``forever`` sets the
    far-future sentinel (see ``mute_util.MUTE_FOREVER``), ``unmute`` clears it.

    Shared by ``PATCH /rooms/{id}/members/me/mute`` and
    ``PATCH /conversations/{id}/mute`` — both mute mechanisms take the exact
    same request shape.
    """

    duration: MuteDuration
