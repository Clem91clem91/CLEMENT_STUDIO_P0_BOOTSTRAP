from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "p1_manifest.json"
WRAPPER = ROOT / "scripts" / "Run-P1Certification.ps1"
REFERENCE = ROOT / "scripts" / "certify_p1_bootstrap_reference.py"


def test_p1_manifest_pins_certified_orchestrator_head() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    assert data["program"] == "CLEMENT_STUDIO_P1"
    assert data["orchestrator"]["repository"] == "Clem91clem91/CLEMENT_STUDIO_ORCHESTRATOR"
    assert data["orchestrator"]["branch"] == "feat/p1-execution-core"
    assert data["orchestrator"]["head"] == "6329530b787a59c13be9654e189a31a4501dab46"
    assert re.fullmatch(r"[0-9a-f]{40}", data["orchestrator"]["head"])


def test_p1_manifest_requires_all_user_visible_gates() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    required = set(data["required_markers"])
    assert {
        "P1_01=PASS",
        "P1_02=PASS",
        "P1_03=PASS",
        "P1_04=PASS",
        "EXECUTION_FABRIC=PASS",
        "AGENT_RUNTIME=PASS",
        "RESOURCE_GUARD=PASS",
        "OBSERVABILITY=PASS",
        "SHADOW_REAL_E2E=PASS",
    } <= required


def test_p1_wrapper_is_fail_closed_and_non_release() -> None:
    text = WRAPPER.read_text(encoding="utf-8-sig")
    assert "P1_PIN_BRANCH_MISMATCH" in text
    assert "P1_PIN_HEAD_MISMATCH" in text
    assert "P1_ORCHESTRATOR_WORKTREE_NOT_CLEAN" in text
    assert "P1_REQUIRED_MARKER_MISSING" in text
    assert "P1_EVIDENCE_MARKER_MISSING" in text
    assert "GLOBAL_P1=PASS" in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text
    lowered = text.lower()
    assert "git merge " not in lowered
    assert "git tag " not in lowered
    assert "gh release create" not in lowered


def test_reference_certifier_exists() -> None:
    assert REFERENCE.is_file()
    text = REFERENCE.read_text(encoding="utf-8-sig")
    assert "P1_BOOTSTRAP_REFERENCE=PASS" in text
