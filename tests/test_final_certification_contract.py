from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "p0_manifest.json"
WRAPPER = ROOT / "scripts" / "Run-FinalP0Certification.ps1"

EXPECTED_HEADS = {
    "P0-01": "6a62a4215d53c56b2c27f71599d18f9faa2bbfac",
    "P0-02": "6ecd68bc230ca3e65ddfd661897dd5a3160fe4df",
    "P0-03": "2b9ca8485d2322378e952d88400ba30767e4b187",
    "P0-04": "a21c08f8242425e0af5883d38f85f3b51515367d",
}


def test_manifest_pins_certified_heads_and_global_certifier() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    components = {item["id"]: item for item in manifest["components"]}

    assert set(components) == set(EXPECTED_HEADS)
    for component_id, expected_head in EXPECTED_HEADS.items():
        assert components[component_id]["expected_head"] == expected_head

    assert components["P0-04"]["certifier"] == "scripts/certify_global_p0.ps1"


def test_final_wrapper_is_ascii_and_fail_closed() -> None:
    raw = WRAPPER.read_bytes()
    raw.decode("ascii")
    text = raw.decode("ascii")

    assert "PINNED_HEADS_BEFORE=PASS" in text
    assert "PINNED_HEADS_AFTER=PASS" in text
    assert "CASCADE_VERDICT=PASS" in text
    assert "GLOBAL_RESULT=PASS" in text
    assert "FINAL_P0_BOOTSTRAP=PASS" in text
    assert "PROTECTED_COMPONENT_EVENTS" in text


def test_final_wrapper_keeps_release_gates_closed() -> None:
    text = WRAPPER.read_text(encoding="ascii").lower()
    forbidden = (
        "git reset",
        "git checkout",
        "git clean",
        "git merge",
        "git tag",
        "git push --force",
        "git push -f",
    )
    for token in forbidden:
        assert token not in text

    assert "merge_executed=no" in text
    assert "tag_created=no" in text
    assert "release_created=no" in text
