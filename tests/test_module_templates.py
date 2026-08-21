from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "templates" / "modules"

WAVE_A = {
    "memory",
    "verified_response",
    "agent_runtime",
    "gpu_manager",
    "knowledge_pipeline",
}


def test_wave_a_templates_exist() -> None:
    assert WAVE_A <= {path.name for path in TEMPLATES.iterdir() if path.is_dir()}


def test_all_template_python_files_compile() -> None:
    python_files = sorted(TEMPLATES.rglob("*.py"))
    assert python_files
    for path in python_files:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")


def test_memory_v11_contains_negative_test_semantics() -> None:
    path = TEMPLATES / "memory" / "memory" / "CLEMENT_STUDIO_ODYSSEUS_MASTER_MEMORY_v1.1.txt"
    text = path.read_text(encoding="utf-8")
    assert "CLAIM_VERDICT != TEST_VERDICT" in text
    assert "FALSE CLAIM REJECTED -> NEGATIVE TEST PASS" in text
    assert "NO EVIDENCE -> NO PASS" in text


def test_apply_template_script_never_merges_or_releases() -> None:
    script = (ROOT / "scripts" / "Apply-ClementStudioModuleTemplates.ps1").read_text(encoding="utf-8-sig")
    lowered = script.lower()
    assert "--draft" in script
    assert "MERGE_EXECUTED=NO" in script
    assert "TAG_CREATED=NO" in script
    assert "RELEASE_CREATED=NO" in script
    assert "gh pr merge" not in lowered
    assert "gh release create" not in lowered
    assert "git tag " not in lowered
    assert "git add ." not in lowered
