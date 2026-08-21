from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "p1_1_manifest.json"
WRAPPER = ROOT / "scripts" / "Run-P11Certification.ps1"


def require(condition: bool, marker: str) -> None:
    if not condition:
        raise RuntimeError(marker)


def main() -> int:
    print("============================================================")
    print("CLEMENT STUDIO - P1.1 BOOTSTRAP REFERENCE")
    print("MODE=PINNED_FAIL_CLOSED")
    print("============================================================")

    data = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    require(data["program"] == "CLEMENT_STUDIO_P1_1", "P1_1_PROGRAM_INVALID")
    require(data["orchestrator"]["repository"] == "Clem91clem91/CLEMENT_STUDIO_ORCHESTRATOR", "P1_1_REPOSITORY_INVALID")
    require(data["orchestrator"]["branch"] == "feat/p1-1-evidence-contract", "P1_1_BRANCH_INVALID")
    require(data["orchestrator"]["head"] == "80ef5bd02c232b17cb04627a8c26430956e33d6c", "P1_1_HEAD_INVALID")

    required = set(data["required_markers"])
    for marker in (
        "P1_1_01_RAW_EVIDENCE=PASS",
        "P1_1_02_PROVENANCE=PASS",
        "P1_1_03_CONSISTENCY=PASS",
        "P1_1_04_FAIL_CLOSED_VERIFIER=PASS",
        "P1_1_SHADOW_REAL=PASS",
        "P1_1_GLOBAL=PASS",
        "FABRICATED_EVIDENCE_BLOCKED=PASS",
        "NO_EVIDENCE_NO_PASS=PASS",
    ):
        require(marker in required, f"P1_1_MARKER_MISSING={marker}")

    text = WRAPPER.read_text(encoding="utf-8-sig")
    require("P1_1_PIN_BRANCH_MISMATCH" in text, "P1_1_BRANCH_GUARD_MISSING")
    require("P1_1_PIN_HEAD_MISMATCH" in text, "P1_1_HEAD_GUARD_MISSING")
    require("P1_1_REQUIRED_MARKER_MISSING" in text, "P1_1_EVIDENCE_GUARD_MISSING")
    require("git merge " not in text.lower(), "P1_1_MERGE_OPERATION_FORBIDDEN")
    require("git tag " not in text.lower(), "P1_1_TAG_OPERATION_FORBIDDEN")
    require("gh release create" not in text.lower(), "P1_1_RELEASE_OPERATION_FORBIDDEN")

    print("P1_1_BOOTSTRAP_PIN=PASS")
    print("P1_1_BOOTSTRAP_FAIL_CLOSED=PASS")
    print("P1_1_BOOTSTRAP_REFERENCE=PASS")
    print("MERGE_EXECUTED=NO")
    print("TAG_CREATED=NO")
    print("RELEASE_CREATED=NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
