"""Tests for boot-time config validation (validate_startup_config / feature_summary)."""

from app.core.config import Settings, feature_summary, validate_startup_config

STRONG_KEY = "x" * 48


def _settings(**overrides) -> Settings:
    base = {"secret_key": STRONG_KEY, "debug": False}
    base.update(overrides)
    return Settings(**base)


def test_placeholder_secret_is_fatal_in_prod():
    fatal, _ = validate_startup_config(_settings(secret_key="change-this-in-production"))
    assert fatal and "SECRET_KEY" in fatal[0]


def test_placeholder_secret_is_warning_in_debug():
    fatal, warns = validate_startup_config(
        _settings(secret_key="change-this-in-production", debug=True)
    )
    assert not fatal
    assert any("SECRET_KEY" in w for w in warns)


def test_empty_secret_is_fatal_in_prod():
    fatal, _ = validate_startup_config(_settings(secret_key=""))
    assert fatal


def test_short_secret_warns_but_boots():
    fatal, warns = validate_startup_config(_settings(secret_key="short-but-real"))
    assert not fatal
    assert any("32 characters" in w for w in warns)


def test_strong_secret_is_clean():
    fatal, warns = validate_startup_config(_settings())
    assert not fatal
    assert not warns


def test_proxy_mode_without_repo_path_warns():
    _, warns = validate_startup_config(
        _settings(microapps_proxy_mode=True, microapps_repo_path="")
    )
    assert any("MICROAPPS_PROXY_MODE" in w for w in warns)


def test_feature_summary_reflects_settings():
    lines = feature_summary(
        _settings(
            microapps_repo_path="/tmp/repo",
            test_user_email="t@example.com",
            test_user_password="pw",
            admin_emails="a@example.com, b@example.com",
        )
    )
    joined = "\n".join(lines)
    assert "micro-apps     : enabled" in joined
    assert "test user      : enabled" in joined
    assert "admin emails   : 2 configured" in joined
