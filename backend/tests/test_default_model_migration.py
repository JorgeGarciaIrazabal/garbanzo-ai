"""Contract checks for the built-in-style default-model migration (047)."""

from pathlib import Path

_SQL = (
    Path(__file__).parents[1] / "migrations/047_default_model_deepseek_v41_flash.sql"
).read_text()


def _sql_without_comments() -> str:
    return "\n".join(line for line in _SQL.splitlines() if not line.strip().startswith("--"))


def test_migration_rewrites_only_builtin_styles():
    sql = _sql_without_comments()
    assert "UPDATE styles" in sql
    assert "WHERE is_builtin = TRUE" in sql
    # User-saved styles must keep their chosen model, so the styles update must
    # not touch rows a user owns.
    styles_block = sql.split("UPDATE styles", 1)[1].split(";", 1)[0]
    assert "user_id" not in styles_block


def test_migration_moves_agent_default_and_scheduled_selections():
    sql = _sql_without_comments()
    assert "UPDATE users" in sql
    assert "UPDATE room_agents" in sql
    assert "UPDATE scheduled_actions" in sql
    # Conversations keep their model — the migration must not rewrite history.
    assert "UPDATE conversations" not in sql


def test_migration_registers_the_new_model_in_the_visibility_catalog():
    assert "INSERT INTO available_models" in _SQL
    assert "'deepseek-v4.1-flash:cloud'" in _SQL
    assert "ON CONFLICT (model_id) DO NOTHING" in _SQL
