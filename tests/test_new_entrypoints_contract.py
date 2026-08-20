from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts" / "Run-ClementP0Cascade.ps1"
LOCATOR = ROOT / "scripts" / "Find-P001AuditEvidence.ps1"


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
    assert 'start-process' in lowered
    assert '-redirectstandardoutput' in lowered
    assert '-redirectstandarderror' in lowered
    assert '$childprocess.exitcode' in lowered
    assert '$output = @(& powershell' not in lowered
    assert re.search(r"}\s*elseif\s*\(", lowered)
    assert not re.search(r"}\s*elif\s*\(", lowered)


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
    for name in ('.venv', 'venv', 'site-packages', '.git', '__pycache__'):
        assert name in text
