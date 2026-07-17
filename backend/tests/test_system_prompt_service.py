"""Tests for SystemPromptService."""

import pytest

from app.services.system_prompt_service import (
    BUILTIN_TEMPLATES,
    SystemPromptService,
)

pytestmark = pytest.mark.asyncio


class TestBuiltinTemplates:
    async def test_seed_creates_all_builtins(self, db_session):
        svc = SystemPromptService(db_session)
        created = await svc.seed_builtin_templates()
        assert created == len(BUILTIN_TEMPLATES)

    async def test_seed_is_idempotent(self, db_session):
        svc = SystemPromptService(db_session)
        first = await svc.seed_builtin_templates()
        second = await svc.seed_builtin_templates()
        assert first == len(BUILTIN_TEMPLATES)
        assert second == 0

    async def test_list_templates_includes_builtins(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.seed_builtin_templates()
        templates = await svc.list_templates(test_user_email)
        names = {t.name for t in templates}
        assert {tpl["name"] for tpl in BUILTIN_TEMPLATES}.issubset(names)

    async def test_list_templates_locale_filter(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.seed_builtin_templates()

        es = await svc.list_templates(test_user_email, locale="es")
        es_builtin_names = {t.name for t in es if t.is_builtin}
        es_expected = {t["name"] for t in BUILTIN_TEMPLATES if t["locale"] == "es"}
        assert es_builtin_names == es_expected
        # No English builtins leak through the filter.
        en_expected = {t["name"] for t in BUILTIN_TEMPLATES if t["locale"] == "en"}
        assert not (es_builtin_names & en_expected)

    async def test_list_templates_locale_falls_back_when_unknown(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.seed_builtin_templates()
        # A locale with no builtins surfaces all builtins (NULL-as-wildcard).
        fr = await svc.list_templates(test_user_email, locale="fr")
        all_builtins = {t.name for t in fr if t.is_builtin}
        assert {t["name"] for t in BUILTIN_TEMPLATES}.issubset(all_builtins)

    async def test_list_templates_locale_with_user_templates(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.seed_builtin_templates()
        await svc.create_template(
            user_id=test_user_email,
            name="Mi plantilla",
            content="Hola.",
        )
        es = await svc.list_templates(test_user_email, locale="es")
        names = {t.name for t in es}
        assert "Mi plantilla" in names


class TestUserTemplates:
    async def test_create_and_fetch(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        tpl = await svc.create_template(
            user_id=test_user_email,
            name="My helper",
            content="You are helpful.",
            description="Personal",
        )
        assert tpl.id
        assert tpl.is_builtin is False

        fetched = await svc.get_template(tpl.id, test_user_email)
        assert fetched is not None
        assert fetched.id == tpl.id

    async def test_update_template(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        tpl = await svc.create_template(user_id=test_user_email, name="Old", content="c")
        updated = await svc.update_template(
            tpl.id, test_user_email, name="New", content="new content"
        )
        assert updated is not None
        assert updated.name == "New"
        assert updated.content == "new content"

    async def test_cannot_update_builtin(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.seed_builtin_templates()
        templates = await svc.list_templates(test_user_email)
        builtin = next(t for t in templates if t.is_builtin)
        result = await svc.update_template(builtin.id, test_user_email, name="hack")
        assert result is None

    async def test_delete_template(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        tpl = await svc.create_template(user_id=test_user_email, name="Trash", content="c")
        assert await svc.delete_template(tpl.id, test_user_email) is True
        assert await svc.get_template(tpl.id, test_user_email) is None

    async def test_cannot_delete_builtin(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.seed_builtin_templates()
        templates = await svc.list_templates(test_user_email)
        builtin = next(t for t in templates if t.is_builtin)
        assert await svc.delete_template(builtin.id, test_user_email) is False

    async def test_user_cannot_see_other_users_templates(self, db_session, test_user_email):
        from app.core.security import hash_password
        from app.models.user import User

        other = User(email="other@example.com", hashed_password=hash_password("x"))
        db_session.add(other)
        await db_session.commit()

        svc = SystemPromptService(db_session)
        await svc.create_template(user_id="other@example.com", name="secret", content="c")
        mine = await svc.list_templates(test_user_email)
        names = {t.name for t in mine}
        assert "secret" not in names


class TestUserDefaultPrompt:
    async def test_default_starts_none(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        assert await svc.get_user_default_prompt(test_user_email) is None

    async def test_set_and_get_default(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.set_user_default_prompt(test_user_email, "Be nice")
        assert await svc.get_user_default_prompt(test_user_email) == "Be nice"

    async def test_clearing_default_normalizes_to_none(self, db_session, test_user_email):
        svc = SystemPromptService(db_session)
        await svc.set_user_default_prompt(test_user_email, "Be nice")
        result = await svc.set_user_default_prompt(test_user_email, "")
        assert result is None
        assert await svc.get_user_default_prompt(test_user_email) is None

    async def test_set_default_for_missing_user_returns_none(self, db_session):
        svc = SystemPromptService(db_session)
        result = await svc.set_user_default_prompt("missing@example.com", "x")
        assert result is None
