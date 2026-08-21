from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "p1_manifest.json"
WRAPPER = ROOT / "scripts" / "Run-P1Certification.ps1"


def main() -> int:
    data = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    orchestrator = data["orchestrator"]
    assert orchestrator["repository"] == "Clem91clem91/CLEMENT_STUDIO_ORCHESTRATOR"
    assert orchestrator["branch"] == "feat/p1-execution-core"
    assert re.fullmatch(r"[0-9a-f]{40}", orchestrator["head"])
    assert orchestrator["head"] == "6329530b787a59c13be9654e189a31a4501dab46"
    required = set(data["required_markers"])
    expected = {
        "P1_01=PASS",
        "P1_02=PASS",
        "P1_03=PASS",
        "P1_04=PASS",
        "EXECUTION_FABRIC=PASS",
        "AGENT_RUNTIME=PASS",
        "RESOURCE_GUARD=PASS",
        "OBSERVABILITY=PASS",
        "SHADOW_REAL_E2E=PASS",
    }
    assert expected <= required
    assert set(data["forbidden_operations"]) == {"merge", "tag", "release"}
    text = WRAPPER.read_text(encoding="utf-8-sig")
    assert "P1_PIN_HEAD_MISMATCH" in text
    assert "P1_REQUIRED_MARKER_MISSING" in text
    assert "GLOBAL_P1=PASS" in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text
    print("P1_BOOTSTRAP_MANIFEST=PASS")
    print("P1_BOOTSTRAP_PIN=PASS")
    print("P1_BOOTSTRAP_MARKERS=PASS")
    print("P1_BOOTSTRAP_REFERENCE=PASS")
    print("MERGE_EXECUTED=NO")
    print("TAG_CREATED=NO")
    print("RELEASE_CREATED=NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
