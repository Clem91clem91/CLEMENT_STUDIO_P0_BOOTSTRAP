from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "Run-P11FinalCertification.ps1"


def test_final_certifier_avoids_case_insensitive_pr_variable_collision() -> None:
    text = SCRIPT.read_text(encoding="utf-8-sig")
    assert "[int]$PrNumber" in text
    assert "$PrInfo =" in text
    assert "[int]$PR" not in text
    assert "$Pr =" not in text


def test_final_certifier_is_fail_closed_and_non_release() -> None:
    text = SCRIPT.read_text(encoding="utf-8-sig")
    assert "PR_HEAD_MISMATCH" in text
    assert "GOVERNANCE_GATE_FAILED" in text
    assert "P1_1_MARKER_MISSING" in text
    assert "DEVELOP_CHANGED_DURING_CERT" in text
    assert "P1_1_GLOBAL=PASS" in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text
    lowered = text.lower()
    assert "gh pr merge" not in lowered
    assert "git tag " not in lowered
    assert "gh release create" not in lowered
