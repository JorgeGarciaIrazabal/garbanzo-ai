"""Service for admin-controlled model availability."""

from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.available_model import AvailableModel


class ModelManagementService:
    """CRUD operations for admin-controlled model visibility."""

    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def list_db_models(self) -> list[AvailableModel]:
        """Return all rows from the ``available_models`` table."""
        result = await self._db.execute(select(AvailableModel).order_by(AvailableModel.model_id))
        return list(result.scalars().all())

    async def get_db_model(self, model_id: str) -> AvailableModel | None:
        return await self._db.get(AvailableModel, model_id)

    async def upsert_from_provider(self, provider_models: list[Any]) -> list[dict[str, Any]]:
        """Sync live provider models into the DB.

        For each model returned by the provider:
        - If a row already exists, leave its ``is_enabled`` unchanged.
        - If it's new, create a row with ``is_enabled=True``.

        Returns a list of dicts combining live metadata + DB state for
        the admin UI.  Also returns rows for DB entries that no longer
        exist in the provider (marked ``is_new=False``, still shown so
        admin can re-enable if the model comes back).
        """
        live_ids = {getattr(m, "id", None) for m in provider_models}
        live_ids.discard(None)
        live_ids_map: dict[str, Any] = {m.id: m for m in provider_models}

        existing = await self.list_db_models()
        existing_ids = {row.model_id for row in existing}

        # Add new models not yet in DB
        for mid in sorted(live_ids - existing_ids):
            self._db.add(AvailableModel(model_id=mid, is_enabled=True))
        if live_ids - existing_ids:
            await self._db.flush()

        # Build merged view
        rows = await self.list_db_models()
        result = []
        for row in rows:
            entry: dict[str, Any] = {
                "model_id": row.model_id,
                "is_enabled": row.is_enabled,
                "is_new": False,
                "updated_at": row.updated_at,
            }
            if row.model_id in live_ids_map:
                m = live_ids_map[row.model_id]
                entry["name"] = getattr(m, "name", row.model_id)
                entry["description"] = getattr(m, "description", None)
                entry["context_length"] = getattr(m, "context_length", None)
            result.append(entry)

        # Also include provider models not in DB yet (shouldn't happen after sync,
        # but just in case)
        for mid in sorted(live_ids - {r.model_id for r in rows}):
            m = live_ids_map[mid]
            result.append(
                {
                    "model_id": mid,
                    "is_enabled": True,
                    "is_new": True,
                    "updated_at": None,
                    "name": getattr(m, "name", mid),
                    "description": getattr(m, "description", None),
                    "context_length": getattr(m, "context_length", None),
                }
            )

        # Sort: enabled first, then by model_id
        result.sort(key=lambda r: (not r["is_enabled"], r["model_id"]))
        return result

    async def set_enabled(self, model_id: str, is_enabled: bool) -> AvailableModel | None:
        """Enable or disable a model.  Creates the row if it doesn't exist."""
        row = await self.get_db_model(model_id)
        if row is None:
            row = AvailableModel(model_id=model_id, is_enabled=is_enabled)
            self._db.add(row)
        else:
            row.is_enabled = is_enabled
        await self._db.flush()
        return row

    async def get_disabled_ids(self) -> set[str]:
        """Return the set of model IDs explicitly disabled by an admin."""
        result = await self._db.execute(
            select(AvailableModel.model_id).where(AvailableModel.is_enabled.is_(False))
        )
        return {r for r in result.scalars().all()}

    async def has_any_rows(self) -> bool:
        """Check if any model rows exist in the DB."""
        result = await self._db.execute(select(AvailableModel.model_id).limit(1))
        return result.scalars().first() is not None
