"""Contract checks for the persisted model-retirement migration."""

from pathlib import Path

import pytest

_SQL = (Path(__file__).parents[1] / "migrations/037_upgrade_llm_models.sql").read_text()


@pytest.mark.parametrize(
    "surface",
    [
        "UPDATE users",
        "UPDATE conversations",
        "UPDATE styles",
        "UPDATE room_agents",
        "UPDATE scheduled_actions",
        "UPDATE shared_items",
        "INSERT INTO available_models",
    ],
)
def test_model_upgrade_covers_every_persisted_configuration_surface(surface):
    assert surface in _SQL


@pytest.mark.parametrize(
    ("old_id", "new_id"),
    [
        ("minimax-m3:cloud", "glm-5.3-flash:cloud"),
        ("glm-5.2:cloud", "glm-5.3:cloud"),
        ("kimi-k2.7-code:cloud", "glm-5.3:cloud"),
        ("deepseek-v4-flash:0731-cloud", "deepseek-v4-flash:cloud"),
        ("deepseek-v4-pro:0813-cloud", "deepseek-v4-pro:cloud"),
        ("qwen3.6:27b", "qwen3.8:27b"),
    ],
)
def test_model_upgrade_contains_the_reviewed_replacement_map(old_id, new_id):
    assert f"('{old_id}', '{new_id}')" in _SQL


def test_pending_shared_styles_update_only_the_model_snapshot():
    assert "jsonb_set(target.payload, '{model_id}'" in _SQL
    assert "target.kind = 'style'" in _SQL


def test_generic_deepseek_flash_is_not_promoted_to_pro():
    assert "('deepseek-v4-flash:cloud', 'deepseek-v4-pro:cloud')" not in _SQL
