import json
from pathlib import Path


def test_wave_a_manifest_has_six_pinned_modules() -> None:
    root = Path(__file__).resolve().parents[1]
    payload = json.loads((root / "config" / "wave_a_manifest.json").read_text(encoding="utf-8"))
    modules = payload["modules"]
    assert payload["program"] == "CLEMENT_STUDIO_WAVE_A"
    assert len(modules) == 6
    assert {item["name"] for item in modules} == {
        "memory",
        "verified_response",
        "agent_runtime",
        "omniroute",
        "gpu_manager",
        "knowledge_pipeline",
    }
    for item in modules:
        assert item["repository"].startswith("CLEMENT_STUDIO_")
        assert item["branch"].startswith("feat/")
        assert len(item["head"]) == 40
    assert "WAVE_A_GLOBAL=PASS" in payload["required_markers"]
    assert payload["forbidden_operations"] == ["merge", "tag", "release"]
