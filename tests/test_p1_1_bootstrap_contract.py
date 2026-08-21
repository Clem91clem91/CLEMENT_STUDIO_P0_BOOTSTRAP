from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "p1_1_manifest.json"
WRAPPER = ROOT / "scripts" / "Run-P11Certification.ps1"
REFERENCE = ROOT / "scripts" / "certify_p1_1_bootstrap_reference.py"


def test_p1_1_manifest_pins_orchestrator_candidate() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    assert data["program"] == "CLEMENT_STUDIO_P1_1"
    assert data["orchestrator"]["repository"] == "Clem91clem91/CLEMENT_STUDIO_ORCHESTRATOR"
    assert data["orchestrator"]["branch"] == "feat/p1-1-evidence-contract"
    assert data["orchestrator"]["head"] == "80ef5bd02c232b17cb04627a8c26430956e33d6c"
    assert re.fullmatch(r"[0-9a-f]{40}", data["orchestrator"]["head"])


def test_p1_1_manifest_requires_all_evidence_gates() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    required = set(data["required_markers"])
    assert {
        "P1_1_01_RAW_EVIDENCE=PASS",
        "P1_1_02_PROVENANCE=PASS",
        "P1_1_03_CONSISTENCY=PASS",
        "P1_1_04_FAIL_CLOSED_VERIFIER=PASS",
        "P1_1_SHADOW_REAL=PASS",
        "P1_1_GLOBAL=PASS",
        "FABRICATED_EVIDENCE_BLOCKED=PASS",
        "NO_EVIDENCE_NO_PASS=PASS",
    } <= required
    assert set(data["forbidden_operations"]) == {"merge", "tag", "release"}


def test_p1_1_wrapper_is_fail_closed_and_non_release() -> None:
    text = WRAPPER.read_text(encoding="utf-8-sig")
    assert "P1_1_PIN_BRANCH_MISMATCH" in text
    assert "P1_1_PIN_HEAD_MISMATCH" in text
    assert "P1_1_ORCHESTRATOR_WORKTREE_NOT_CLEAN" in text
    assert "P1_1_REQUIRED_MARKER_MISSING" in text
    assert "P1_1_GLOBAL=PASS" in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text
    lowered = text.lower()
    assert "git merge " not in lowered
    assert "git tag " not in lowered
    assert "gh release create" not in lowered


def test_p1_1_reference_certifier_exists() -> None:
    assert REFERENCE.is_file()
    text = REFERENCE.read_text(encoding="utf-8-sig")
    assert "P1_1_BOOTSTRAP_REFERENCE=PASS" in text
