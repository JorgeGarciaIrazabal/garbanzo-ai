"""Tests for MicroappWorkspaceManager against a real temp git repo.

A bare repo acts as the ``origin`` remote; a working repo (with fake apps/,
houses/ and scripts/dev-server.js) is the micro-apps monorepo. Subprocess
spawns (dev server + opencode) and the opencode readiness probe are mocked so
no node/opencode process is ever launched.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.microapp_workspace import (
    FeatureDisabledError,
    MicroappWorkspaceManager,
    WorkspaceError,
    slugify_email,
)


class FakeProc:
    """Stand-in for subprocess.Popen: always reports 'alive'."""

    def __init__(self) -> None:
        self.pid = 424242
        self._killed = False

    def poll(self):
        return None  # None == still running

    def kill(self):
        self._killed = True


def _git(cwd: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", "-C", str(cwd), *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return res.stdout


@pytest.fixture()
def repos(tmp_path: Path):
    """Create a bare remote + a working micro-apps repo; return (repo, bare)."""
    bare = tmp_path / "remote.git"
    repo = tmp_path / "micro-apps"
    bare.mkdir()
    repo.mkdir()

    _git(bare, "init", "--bare", "-b", "main")
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "dev@example.com")
    _git(repo, "config", "user.name", "Dev")

    # Fake repo contents.
    (repo / "scripts").mkdir()
    (repo / "scripts" / "dev-server.js").write_text("// stub\n")
    (repo / "houses").mkdir()
    (repo / "houses" / "tiny-cabin.house.json").write_text('{"name":"Tiny Cabin","floors":[]}\n')
    (repo / "registry.json").write_text(
        '{"version":1,"apps":[{"id":"house-designer","name":"House Designer",'
        '"path":"house-designer/"}]}\n'
    )
    apps = repo / "apps" / "house-designer"
    apps.mkdir(parents=True)
    (apps / "package.json").write_text('{"name":"house-designer"}\n')

    _git(repo, "add", "-A")
    _git(repo, "commit", "-m", "initial")
    _git(repo, "remote", "add", "origin", str(bare))
    _git(repo, "push", "-u", "origin", "main")

    return repo, bare


@pytest.fixture()
def manager(repos):
    repo, _bare = repos
    settings = Settings(
        secret_key="test",
        database_url="sqlite+aiosqlite:///:memory:",
        microapps_repo_path=str(repo),
        microapps_dev_port_base=8100,
    )
    mgr = MicroappWorkspaceManager(
        settings,
        spawn=lambda cmd, cwd, env: FakeProc(),
        house_validator=lambda wt, rel: (True, "valid"),
        auto_install_deps=False,
    )
    # Never actually poll opencode.
    mgr._wait_opencode_ready = lambda base, proc: True  # type: ignore[assignment]
    return mgr


EMAIL = "jorge.girazabal@gmail.com"


def test_slugify_email():
    assert slugify_email(EMAIL) == "jorge-girazabal-gmail-com"
    assert slugify_email("  A.B+C@X.io ") == "a-b-c-x-io"
    assert slugify_email("@@@") == "user"


def test_dev_port_stable_and_in_band(manager):
    slug = slugify_email(EMAIL)
    p1 = manager.dev_port_for(slug)
    p2 = manager.dev_port_for(slug)
    assert p1 == p2
    assert 8100 <= p1 < 8100 + 400


def test_ensure_worktree_idempotent(manager):
    ws1 = manager.ensure_sync(EMAIL)
    assert ws1.state == "ready"
    assert ws1.path.is_dir()
    assert ws1.opencode_ready is True

    listing = _git(manager.repo_path, "worktree", "list", "--porcelain")
    count_before = listing.count("worktree ")

    ws2 = manager.ensure_sync(EMAIL)
    assert ws2.path == ws1.path
    listing2 = _git(manager.repo_path, "worktree", "list", "--porcelain")
    assert listing2.count("worktree ") == count_before  # no duplicate worktree


def test_seeds_opencode_config(manager):
    ws = manager.ensure_sync(EMAIL)
    cfg = ws.path / "opencode.json"
    assert cfg.is_file()
    data = json.loads(cfg.read_text())
    assert "ollama" in data["provider"]
    # Internal planning tools disabled — see _seed_opencode_config rationale.
    assert data["tools"] == {"todowrite": False, "todoread": False}


def test_changes_parses_porcelain(manager):
    ws = manager.ensure_sync(EMAIL)
    # Modify a tracked file and add an untracked one.
    (ws.path / "houses" / "tiny-cabin.house.json").write_text(
        '{"name":"Tiny Cabin","floors":[1,2,3]}\n'
    )
    (ws.path / "newfile.txt").write_text("hello\n")

    summary = manager.changes(EMAIL)
    by_path = {f.path: f for f in summary.files}
    assert "houses/tiny-cabin.house.json" in by_path
    assert by_path["houses/tiny-cabin.house.json"].status == "M"
    assert by_path["houses/tiny-cabin.house.json"].plus >= 1
    assert "newfile.txt" in by_path
    assert by_path["newfile.txt"].status == "?"
    assert summary.ahead == 0


def test_publish_commits_rebases_pushes(manager, repos):
    _repo, bare = repos
    ws = manager.ensure_sync(EMAIL)
    (ws.path / "houses" / "tiny-cabin.house.json").write_text(
        '{"name":"Tiny Cabin","floors":[9]}\n'
    )

    result = manager.publish(EMAIL, "make cabin bigger")
    assert result.committed is True
    assert result.pushed is True
    assert result.commit

    # The bare remote's main now carries the new commit.
    log = _git(bare, "log", "--oneline", "main")
    assert "make cabin bigger" in log


def test_publish_rejects_invalid_house(repos):
    repo, _bare = repos
    settings = Settings(
        secret_key="test",
        database_url="sqlite+aiosqlite:///:memory:",
        microapps_repo_path=str(repo),
    )
    mgr = MicroappWorkspaceManager(
        settings,
        spawn=lambda cmd, cwd, env: FakeProc(),
        house_validator=lambda wt, rel: (False, "schema error at line 3"),
        auto_install_deps=False,
    )
    mgr._wait_opencode_ready = lambda base, proc: True  # type: ignore[assignment]

    ws = mgr.ensure_sync(EMAIL)
    (ws.path / "houses" / "tiny-cabin.house.json").write_text('{"broken":true}\n')

    with pytest.raises(WorkspaceError, match="Invalid house"):
        mgr.publish(EMAIL, "oops")


def test_revert_scopes_to_paths(manager):
    ws = manager.ensure_sync(EMAIL)
    house = ws.path / "houses" / "tiny-cabin.house.json"
    reg = ws.path / "registry.json"
    original_house = house.read_text()
    original_reg = reg.read_text()

    house.write_text('{"name":"changed","floors":[]}\n')
    reg.write_text('{"version":2,"apps":[]}\n')

    # Revert only the house; registry.json stays modified.
    summary = manager.revert(EMAIL, paths=["houses/tiny-cabin.house.json"])
    assert house.read_text() == original_house
    assert reg.read_text() != original_reg
    changed_paths = {f.path for f in summary.files}
    assert "registry.json" in changed_paths
    assert "houses/tiny-cabin.house.json" not in changed_paths


def test_revert_all_requires_flag(manager):
    manager.ensure_sync(EMAIL)
    ws = manager.status(EMAIL)
    (ws.path / "registry.json").write_text('{"version":9}\n')

    with pytest.raises(WorkspaceError, match="explicit 'all' flag"):
        manager.revert(EMAIL, paths=None, all_changes=False)

    summary = manager.revert(EMAIL, paths=None, all_changes=True)
    assert summary.files == []


def test_create_house_from_template(manager):
    manager.ensure_sync(EMAIL)
    rel = manager.create_house(EMAIL, "My New Home")
    assert rel == "houses/my-new-home.house.json"
    ws = manager.status(EMAIL)
    assert (ws.path / rel).is_file()

    with pytest.raises(WorkspaceError, match="already exists"):
        manager.create_house(EMAIL, "My New Home")


def test_feature_disabled_manager():
    # Explicit empty path — do not inherit a real MICROAPPS_REPO_PATH from .env.
    mgr = MicroappWorkspaceManager(
        Settings(
            secret_key="t",
            database_url="sqlite+aiosqlite:///:memory:",
            microapps_repo_path="",
        )
    )
    assert mgr.enabled is False
    with pytest.raises(FeatureDisabledError):
        mgr.status(EMAIL)
