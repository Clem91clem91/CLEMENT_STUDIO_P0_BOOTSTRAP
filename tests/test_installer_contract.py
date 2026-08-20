from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "Install-ClementP0Cascade.ps1"


def test_installer_exists_and_is_ascii_for_windows_powershell_51():
    raw = SCRIPT.read_bytes()
    assert raw
    raw.decode("ascii")


def test_installer_has_no_destructive_git_shortcuts():
    text = SCRIPT.read_text(encoding="ascii").lower()
    forbidden = (
        "git reset",
        "git checkout",
        "git clean",
        "git merge",
        "git tag",
        "git push --force",
        "git push -f",
    )
    for token in forbidden:
        assert token not in text


def test_installer_uses_fast_forward_and_worktree_gate():
    text = SCRIPT.read_text(encoding="ascii")
    assert "git pull --ff-only" in text
    assert "git status --porcelain" in text
    assert "BLOCKED_PROTECTED_WORKTREE" in text
    assert "SYNC=SKIPPED_PROTECTED_EXISTING" in text


def test_installer_preserves_release_gate():
    text = SCRIPT.read_text(encoding="ascii")
    assert "MERGE_ALLOWED=NO" in text
    assert "TAG_ALLOWED=NO" in text
    assert "RELEASE_ALLOWED=NO" in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text


def test_manifest_cascade_order_is_explicit():
    import json

    manifest = json.loads((ROOT / "config" / "p0_manifest.json").read_text(encoding="utf-8"))
    components = {item["id"]: item for item in manifest["components"]}
    assert components["P0-02"]["depends_on"] == ["P0-01"]
    assert set(components["P0-04"]["depends_on"]) == {"P0-01", "P0-02", "P0-03"}
    assert components["P0-01"]["protected_existing"] is True
