from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts" / "Run-WaveACertification.ps1"


def test_wave_a_wrapper_allows_only_untracked_generated_python_artifacts() -> None:
    text = WRAPPER.read_text(encoding="utf-8")
    assert "Test-IgnorableGeneratedUntracked" in text
    assert 'StartsWith("?? ")' in text
    assert "__pycache__" in text
    assert "\\.egg-info/" in text
    assert "\\.pytest_cache/" in text
    assert "MODULE_WORKTREE_NOT_CLEAN" in text
    assert "MODULE_POST_SYNC_WORKTREE_NOT_CLEAN" in text


def test_wave_a_wrapper_does_not_use_destructive_git_clean() -> None:
    text = WRAPPER.read_text(encoding="utf-8").lower()
    assert "git clean" not in text
    assert "reset --hard" not in text
