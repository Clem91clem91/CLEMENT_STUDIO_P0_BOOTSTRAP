from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CREATE_SCRIPT = ROOT / "scripts" / "New-ClementStudioModuleRepos.ps1"
APPLY_SCRIPT = ROOT / "scripts" / "Apply-ClementStudioModuleTemplates.ps1"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_missing_repository_probe_is_explicitly_non_fatal() -> None:
    text = _text(CREATE_SCRIPT)
    assert "function Test-GitHubRepositoryExists" in text
    assert '$PreviousErrorActionPreference = $ErrorActionPreference' in text
    assert '$ErrorActionPreference = "Continue"' in text
    assert "1>$null 2>$null" in text
    assert 'Write-Host "REPOSITORY_STATUS=ABSENT"' in text


def test_branch_protection_failure_is_partial_not_native_terminating_error() -> None:
    text = _text(CREATE_SCRIPT)
    assert '$ProtectionExitCode = $LASTEXITCODE' in text
    assert 'BRANCH_PROTECTION=$FullRepo PARTIAL' in text


def test_template_script_uses_safe_repository_probe() -> None:
    text = _text(APPLY_SCRIPT)
    assert "function Test-GitHubRepositoryExists" in text
    assert '$ErrorActionPreference = "Continue"' in text
    assert 'REMOTE_REPOSITORY_NOT_FOUND=$FullRepo' in text


def test_remote_feature_branch_probe_does_not_use_failing_rev_parse() -> None:
    text = _text(APPLY_SCRIPT)
    assert "function Test-RemoteFeatureBranchExists" in text
    assert 'branch --remotes --list "origin/$FeatureBranch"' in text
    assert 'rev-parse --verify "origin/$FeatureBranch"' not in text
