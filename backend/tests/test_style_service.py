"""Tests for StyleService — CRUD, ownership isolation, default selection,
and system-prompt-template FK behavior (Idea 2, "Styles" — subtask 2).

Mirrors ``test_scheduled_action_service.py`` in structure.
"""

import pytest

from app.core.security import hash_password
from app.models.system_prompt import SystemPromptTemplate
from app.models.user import User
from app.services.style_service import BuiltinReadOnlyError, StyleService

pytestmark = pytest.mark.asyncio


async def _other_user(db_session, email: str = "other@example.com") -> str:
    db_session.add(User(email=email, hashed_password=hash_password("x")))
    await db_session.commit()
    return email


async def _template(db_session, user_id: str | None, name: str = "tpl") -> SystemPromptTemplate:
    tpl = SystemPromptTemplate(
        id=f"tpl-{name}",
        user_id=user_id,
        name=name,
        content="You are a helpful assistant.",
        is_builtin=user_id is None,
    )
    db_session.add(tpl)
    await db_session.commit()
    await db_session.refresh(tpl)
    return tpl


class TestStyleServiceCreate:
    async def test_create_minimal(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="Quick Answers", model_id="llama3.2")
        assert style.id
        assert style.name == "Quick Answers"
        assert style.model_id == "llama3.2"
        assert style.thinking_level is None
        assert style.system_prompt_template_id is None
        assert style.is_default is False

    async def test_create_with_all_fields(self, db_session, test_user_email):
        svc = StyleService(db_session)
        tpl = await _template(db_session, test_user_email)
        style = await svc.create(
            user_id=test_user_email,
            name="Deep Work",
            model_id="qwen3",
            thinking_level="high",
            system_prompt_template_id=tpl.id,
            is_default=True,
        )
        assert style.thinking_level == "high"
        assert style.system_prompt_template_id == tpl.id
        assert style.is_default is True

    async def test_create_with_builtin_template_allowed(self, db_session, test_user_email):
        svc = StyleService(db_session)
        tpl = await _template(db_session, user_id=None, name="builtin")
        style = await svc.create(
            user_id=test_user_email,
            name="x",
            model_id="llama3.2",
            system_prompt_template_id=tpl.id,
        )
        assert style.system_prompt_template_id == tpl.id

    async def test_create_with_missing_template_raises(self, db_session, test_user_email):
        svc = StyleService(db_session)
        with pytest.raises(ValueError, match="not found"):
            await svc.create(
                user_id=test_user_email,
                name="x",
                model_id="llama3.2",
                system_prompt_template_id="does-not-exist",
            )

    async def test_create_with_other_users_template_raises(self, db_session, test_user_email):
        other = await _other_user(db_session)
        tpl = await _template(db_session, user_id=other, name="private")
        svc = StyleService(db_session)
        with pytest.raises(ValueError, match="not found"):
            await svc.create(
                user_id=test_user_email,
                name="x",
                model_id="llama3.2",
                system_prompt_template_id=tpl.id,
            )


class TestStyleServiceIsDefault:
    async def test_second_default_unsets_first(self, db_session, test_user_email):
        svc = StyleService(db_session)
        first = await svc.create(
            user_id=test_user_email, name="a", model_id="llama3.2", is_default=True
        )
        second = await svc.create(
            user_id=test_user_email, name="b", model_id="llama3.2", is_default=True
        )
        refreshed_first = await svc.get(first.id, test_user_email)
        assert refreshed_first is not None
        assert refreshed_first.is_default is False
        assert second.is_default is True

    async def test_update_to_default_unsets_previous(self, db_session, test_user_email):
        svc = StyleService(db_session)
        first = await svc.create(
            user_id=test_user_email, name="a", model_id="llama3.2", is_default=True
        )
        second = await svc.create(user_id=test_user_email, name="b", model_id="llama3.2")

        updated = await svc.update(second.id, test_user_email, is_default=True)
        assert updated is not None
        assert updated.is_default is True

        refreshed_first = await svc.get(first.id, test_user_email)
        assert refreshed_first is not None
        assert refreshed_first.is_default is False

    async def test_default_is_scoped_per_user(self, db_session, test_user_email):
        other = await _other_user(db_session)
        svc = StyleService(db_session)
        mine = await svc.create(
            user_id=test_user_email, name="mine", model_id="llama3.2", is_default=True
        )
        theirs = await svc.create(
            user_id=other, name="theirs", model_id="llama3.2", is_default=True
        )
        # Each user's default is independent — creating one doesn't touch
        # the other user's row.
        assert (await svc.get(mine.id, test_user_email)).is_default is True
        assert (await svc.get(theirs.id, other)).is_default is True

    async def test_explicit_unset_default(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(
            user_id=test_user_email, name="a", model_id="llama3.2", is_default=True
        )
        updated = await svc.update(style.id, test_user_email, is_default=False)
        assert updated is not None
        assert updated.is_default is False


class TestStyleServiceReadsAndIsolation:
    async def test_get_scoped_to_user(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")
        assert (await svc.get(style.id, test_user_email)) is not None
        assert (await svc.get(style.id, "other@example.com")) is None

    async def test_list_for_user_excludes_others(self, db_session, test_user_email):
        other = await _other_user(db_session)
        svc = StyleService(db_session)
        await svc.create(user_id=test_user_email, name="mine-a", model_id="llama3.2")
        await svc.create(user_id=test_user_email, name="mine-b", model_id="llama3.2")
        await svc.create(user_id=other, name="theirs", model_id="llama3.2")

        mine = await svc.list_for_user(test_user_email)
        assert {s.name for s in mine} == {"mine-a", "mine-b"}

        theirs = await svc.list_for_user(other)
        assert {s.name for s in theirs} == {"theirs"}


class TestStyleServiceUpdate:
    async def test_update_name_and_model(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="orig", model_id="llama3.2")
        updated = await svc.update(style.id, test_user_email, name="renamed", model_id="qwen3")
        assert updated is not None
        assert updated.name == "renamed"
        assert updated.model_id == "qwen3"

    async def test_update_thinking_level_set_and_reset(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")

        updated = await svc.update(
            style.id, test_user_email, thinking_level="high", set_thinking_level=True
        )
        assert updated is not None
        assert updated.thinking_level == "high"

        reset = await svc.update(
            style.id, test_user_email, thinking_level=None, set_thinking_level=True
        )
        assert reset is not None
        assert reset.thinking_level is None

    async def test_update_without_set_flag_leaves_thinking_level_unchanged(
        self, db_session, test_user_email
    ):
        svc = StyleService(db_session)
        style = await svc.create(
            user_id=test_user_email, name="x", model_id="llama3.2", thinking_level="medium"
        )
        updated = await svc.update(style.id, test_user_email, name="renamed")
        assert updated is not None
        assert updated.thinking_level == "medium"

    async def test_update_template_id_set_and_clear(self, db_session, test_user_email):
        svc = StyleService(db_session)
        tpl = await _template(db_session, test_user_email)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")

        updated = await svc.update(
            style.id,
            test_user_email,
            system_prompt_template_id=tpl.id,
            set_template_id=True,
        )
        assert updated is not None
        assert updated.system_prompt_template_id == tpl.id

        cleared = await svc.update(
            style.id,
            test_user_email,
            system_prompt_template_id=None,
            set_template_id=True,
        )
        assert cleared is not None
        assert cleared.system_prompt_template_id is None

    async def test_update_with_missing_template_raises(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")
        with pytest.raises(ValueError, match="not found"):
            await svc.update(
                style.id,
                test_user_email,
                system_prompt_template_id="does-not-exist",
                set_template_id=True,
            )

    async def test_update_missing_style_returns_none(self, db_session, test_user_email):
        svc = StyleService(db_session)
        assert await svc.update("missing", test_user_email, name="x") is None

    async def test_update_wrong_user_returns_none(self, db_session, test_user_email):
        other = await _other_user(db_session)
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")
        assert await svc.update(style.id, other, name="hijacked") is None
        # Untouched for the real owner.
        assert (await svc.get(style.id, test_user_email)).name == "x"


class TestStyleServiceDelete:
    async def test_delete_existing(self, db_session, test_user_email):
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")
        assert await svc.delete(style.id, test_user_email) is True
        assert await svc.get(style.id, test_user_email) is None

    async def test_delete_missing_returns_false(self, db_session, test_user_email):
        svc = StyleService(db_session)
        assert await svc.delete("missing", test_user_email) is False

    async def test_delete_wrong_user_returns_false(self, db_session, test_user_email):
        other = await _other_user(db_session)
        svc = StyleService(db_session)
        style = await svc.create(user_id=test_user_email, name="x", model_id="llama3.2")
        assert await svc.delete(style.id, other) is False
        assert await svc.get(style.id, test_user_email) is not None


class TestStyleTemplateDeletionBehavior:
    async def test_deleting_template_nulls_reference_not_style(self, db_session, test_user_email):
        """The style must survive its template being deleted (ON DELETE
        SET NULL) — deleting a template only clears the prompt half of the
        bundle, it never cascades to destroy the whole style.
        """
        svc = StyleService(db_session)
        tpl = await _template(db_session, test_user_email)
        style = await svc.create(
            user_id=test_user_email,
            name="Deep Work",
            model_id="qwen3",
            thinking_level="high",
            system_prompt_template_id=tpl.id,
        )

        await db_session.delete(tpl)
        await db_session.commit()
        # The test session has expire_on_commit=False (see conftest), so the
        # already-loaded ``style`` object's Python-side attributes wouldn't
        # otherwise reflect a DB-level cascade the ORM never issued itself.
        # A fresh request-scoped session in production wouldn't have this
        # staleness — it would query cold and see the post-cascade row. Use
        # an explicit async-safe refresh rather than expire_all(), which
        # would trigger a sync attribute-reload path AsyncSession can't run
        # outside a greenlet context.
        await db_session.refresh(style)

        survivor = await svc.get(style.id, test_user_email)
        assert survivor is not None
        assert survivor.system_prompt_template_id is None
        # The rest of the bundle is untouched.
        assert survivor.model_id == "qwen3"
        assert survivor.thinking_level == "high"


class TestStyleServiceBuiltins:
    """Built-in styles are shared, read-only, and surface for every user."""

    async def _seed_builtins(self, db_session) -> int:
        """Seed the built-in templates + styles without running startup.
        Returns the number of built-in styles created this call.
        """
        from app.services.system_prompt_service import SystemPromptService

        await SystemPromptService(db_session).seed_builtin_templates()
        return await StyleService(db_session).seed_builtin_styles()

    async def test_seed_creates_styles_per_locale(self, db_session):
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        # Every user sees the built-ins, even without an account row.
        listed = await svc.list_for_user("anyone@example.com")
        names = sorted((s.name, s.locale) for s in listed if s.is_builtin)
        # 5 English + 5 Spanish built-ins (see StyleService.BUILTIN_STYLES).
        # "Coding"/"Programación" were dropped from the seed list and pruned by
        # migration 031, so neither should appear.
        assert ("Concise", "en") in names
        assert ("Truth Seeker", "en") in names
        assert ("Conciso", "es") in names
        assert ("Buscador de la verdad", "es") in names
        assert ("Coding", "en") not in names
        assert ("Programación", "es") not in names
        assert sum(1 for s in listed if s.is_builtin) == 10

    async def test_seed_is_idempotent(self, db_session):
        await self._seed_builtins(db_session)
        first = await self._seed_builtins(db_session)
        assert first == 0

    async def test_builtins_link_to_builtin_templates(self, db_session):
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user("anyone@example.com")
        for s in listed:
            if not s.is_builtin:
                continue
            assert s.system_prompt_template_id is not None
            tpl = await db_session.get(SystemPromptTemplate, s.system_prompt_template_id)
            assert tpl is not None
            assert tpl.is_builtin is True
            assert tpl.locale == s.locale

    async def test_builtins_are_not_default_by_default(self, db_session):
        # Fresh seed: no built-in has a per-user default pointer set for a
        # brand-new user, so list_for_user reports is_default=False on all.
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user("anyone@example.com")
        assert all(not s.is_default for s in listed if s.is_builtin)

    async def test_set_builtin_as_default_for_user(self, db_session, test_user_email):
        # A built-in style can be set as the per-user default for new chats
        # (user-report f1af13d5) — it writes user.default_style_id, not the
        # shared row's is_default flag.
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user(test_user_email)
        builtin = next(s for s in listed if s.is_builtin)

        updated = await svc.update(builtin.id, test_user_email, is_default=True)
        assert updated.is_default is True

        # The shared row is *not* mutated — only the per-user pointer moves.
        # Any other user still sees the built-in as non-default.
        other_list = await svc.list_for_user("someone_else@example.com")
        same_builtin = next(s for s in other_list if s.id == builtin.id)
        assert same_builtin.is_default is False

        # Setting a different user-owned style as default unsets the built-in.
        owned = await svc.create(
            user_id=test_user_email, name="mine", model_id="llama3.2", is_default=True
        )
        relisted = await svc.list_for_user(test_user_email)
        assert owned.is_default is True
        same_builtin_after = next(s for s in relisted if s.id == builtin.id)
        assert same_builtin_after.is_default is False

        # The per-user pointer is the source of truth.
        user = await db_session.get(User, test_user_email)
        assert user is not None
        assert user.default_style_id == owned.id
        # is_default=False on a built-in that *is* the user's default clears it.
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user(test_user_email)
        builtin = next(s for s in listed if s.is_builtin)
        await svc.update(builtin.id, test_user_email, is_default=True)
        cleared = await svc.update(builtin.id, test_user_email, is_default=False)
        assert cleared.is_default is False

    async def test_update_builtins_raises(self, db_session, test_user_email):
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user(test_user_email)
        builtin = next(s for s in listed if s.is_builtin)
        with pytest.raises(BuiltinReadOnlyError):
            await svc.update(builtin.id, test_user_email, name="hijacked")

    async def test_update_builtins_model_raises(self, db_session, test_user_email):
        # Only is_default is writable on a built-in; other content fields 403.
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user(test_user_email)
        builtin = next(s for s in listed if s.is_builtin)
        with pytest.raises(BuiltinReadOnlyError):
            await svc.update(builtin.id, test_user_email, model_id="other-model")
        with pytest.raises(BuiltinReadOnlyError):
            await svc.update(
                builtin.id, test_user_email, set_thinking_level=True, thinking_level="low"
            )

    async def test_clear_builtin_default(self, db_session, test_user_email):
        # is_default=False on a built-in that *is* the user's default clears it.
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user(test_user_email)
        builtin = next(s for s in listed if s.is_builtin)
        await svc.update(builtin.id, test_user_email, is_default=True)
        cleared = await svc.update(builtin.id, test_user_email, is_default=False)
        assert cleared.is_default is False

    async def test_delete_builtins_raises(self, db_session, test_user_email):
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        listed = await svc.list_for_user(test_user_email)
        builtin = next(s for s in listed if s.is_builtin)
        with pytest.raises(BuiltinReadOnlyError):
            await svc.delete(builtin.id, test_user_email)

    async def test_list_orders_user_styles_before_builtins(self, db_session, test_user_email):
        await self._seed_builtins(db_session)
        svc = StyleService(db_session)
        await svc.create(user_id=test_user_email, name="mine", model_id="llama3.2")
        listed = await svc.list_for_user(test_user_email)
        # The user's own styles come first, built-ins after.
        first_builtin = next(i for i, s in enumerate(listed) if s.is_builtin)
        assert all(not listed[i].is_builtin for i in range(first_builtin))
        assert any(s.is_builtin for s in listed)
