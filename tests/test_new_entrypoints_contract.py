from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts" / "Run-ClementP0Cascade.ps1"
LOCATOR = ROOT / "scripts" / "Find-P001AuditEvidence.ps1"
GITIGNORE = ROOT / ".gitignore"


def test_new_powershell_entrypoints_are_ascii():
    WRAPPER.read_bytes().decode("ascii")
    LOCATOR.read_bytes().decode("ascii")


def test_wrapper_reports_partial_for_protected_components():
    text = WRAPPER.read_text(encoding="ascii")
    assert "SYNC=SKIPPED_PROTECTED_EXISTING" in text
    assert 'Verdict = "PARTIAL"' in text
    assert "CASCADE_VERDICT=$Verdict" in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text


def test_wrapper_uses_process_exit_code_not_native_stderr_as_failure_signal():
    text = WRAPPER.read_text(encoding="ascii")
    lowered = text.lower()
    assert "start-process" in lowered
    assert "-redirectstandardoutput" in lowered
    assert "-redirectstandarderror" in lowered
    assert "$childprocess.exitcode" in lowered
    assert "$output = @(& powershell" not in lowered
    assert re.search(r"}\s*elseif\s*\(", lowered)
    assert not re.search(r"}\s*elif\s*\(", lowered)


def test_wrapper_isolates_sync_component_return_contract():
    text = WRAPPER.read_text(encoding="ascii")
    assert "$SyncItems = @(Sync-Component" in text
    assert "$Sync = $SyncItems[-1]" in text
    assert "SYNC_COMPONENT_RETURN_EMPTY" in text
    assert "SYNC_COMPONENT_CONTRACT_INVALID" in text
    assert "SYNC_RETURN_CONTRACT_PATCH=PASS" in text


def test_wrapper_isolates_venv_install_return_contract():
    text = WRAPPER.read_text(encoding="ascii")
    assert "$VenvItems = @(Ensure-VenvAndInstall" in text
    assert "$VenvPython = [string]$VenvItems[-1]" in text
    assert "VENV_INSTALL_RETURN_EMPTY" in text
    assert "VENV_INSTALL_CONTRACT_INVALID" in text
    assert "VENV_RETURN_CONTRACT_PATCH=PASS" in text


def test_wrapper_isolates_bootstrap_self_test_venv_contract():
    text = WRAPPER.read_text(encoding="ascii")
    assert "$BootstrapVenvItems = @(Ensure-VenvAndInstall" in text
    assert "$BootstrapVenv = [string]$BootstrapVenvItems[-1]" in text
    assert "BOOTSTRAP_VENV_RETURN_EMPTY" in text
    assert "BOOTSTRAP_VENV_CONTRACT_INVALID_VALUE" in text
    assert "BOOTSTRAP_VENV_RETURN_CONTRACT_PATCH=PASS" in text
    assert "CASCADE_PATCH_POINT_NOT_FOUND=BOOTSTRAP_VENV" in text
    assert "CASCADE_PATCH_FAILED=BOOTSTRAP_VENV" in text


def test_wrapper_executes_auditable_patched_installer_copy():
    text = WRAPPER.read_text(encoding="ascii")
    assert "Install-ClementP0Cascade.patched-" in text
    assert "Set-Content -LiteralPath $PatchedInstaller" in text
    assert '"-File", $PatchedInstaller' in text
    assert "PATCHED_INSTALLER=$PatchedInstaller" in text


def test_wrapper_tolerates_only_known_untracked_generated_metadata():
    text = WRAPPER.read_text(encoding="ascii")
    assert "Enable-SafeGeneratedExcludes" in text
    assert '$Text.StartsWith("?? ")' in text
    assert '"*.egg-info/"' in text
    assert '"build/"' in text
    assert '"dist/"' in text
    assert '.git\\info\\exclude' in text
    assert "SKIPPED_UNSAFE_DIRTY" in text
    assert "SAFE_GENERATED_EXCLUDE_FAILED" in text


def test_wrapper_safe_generated_preflight_never_deletes_generated_files():
    text = WRAPPER.read_text(encoding="ascii").lower()
    assert "remove-item" in text  # wrapper logs are intentionally rotated
    for generated in ("egg-info", "build", "dist"):
        assert not re.search(rf"remove-item[^\n]*{generated}", text)
    assert "git clean" not in text
    assert "git reset" not in text
    assert "git checkout" not in text


def test_bootstrap_ignores_editable_build_metadata():
    text = GITIGNORE.read_text(encoding="utf-8")
    for pattern in ("*.egg-info/", "build/", "dist/"):
        assert pattern in text


def test_locator_is_read_only_and_pins_recovered_hashes():
    text = LOCATOR.read_text(encoding="ascii")
    assert "23726C8DD8FEA5D79636DF27E6AB8CF55BDE073138D9D5A60B5F7B455C958E49" in text
    assert "588EE8589278517FA66CFA8DF998E00E163C31DF21D6CC2425F6E95AD4775084" in text
    assert "17ABD5B090E4077E28C887A3E2F1B0269FF0DE447718B1746E21780CD1A83F25" in text
    forbidden = ("remove-item", "set-content", "move-item", "copy-item", "git reset", "git checkout")
    lowered = text.lower()
    for token in forbidden:
        assert token not in lowered


def test_locator_excludes_dependency_and_git_directories():
    text = LOCATOR.read_text(encoding="ascii")
    for name in (".venv", "venv", "site-packages", ".git", "__pycache__"):
        assert name in text
