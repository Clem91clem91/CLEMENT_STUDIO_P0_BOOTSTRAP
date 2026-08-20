import json
from pathlib import Path

import pytest

from clement_p0_bootstrap import BootstrapManifestError, load_manifest, plan_components


def test_repository_manifest_has_expected_order() -> None:
    root = Path(__file__).resolve().parents[1]
    _, components = load_manifest(root / "config" / "p0_manifest.json")
    ordered = plan_components(components)
    ids = [component.id for component in ordered]
    assert ids.index("P0-01") < ids.index("P0-02")
    assert ids.index("P0-01") < ids.index("P0-04")
    assert ids.index("P0-02") < ids.index("P0-04")
    assert ids.index("P0-03") < ids.index("P0-04")


def test_planner_is_deterministic() -> None:
    root = Path(__file__).resolve().parents[1]
    _, components = load_manifest(root / "config" / "p0_manifest.json")
    first = [c.id for c in plan_components(components)]
    second = [c.id for c in plan_components(tuple(reversed(components)))]
    assert first == second


def test_cycle_is_rejected(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "schema_version": "1.0.0",
                "root": str(tmp_path),
                "components": [
                    {"id": "A", "name": "A", "repository": "x/A", "branch": "feat/a", "local_dir": "A", "depends_on": ["B"]},
                    {"id": "B", "name": "B", "repository": "x/B", "branch": "feat/b", "local_dir": "B", "depends_on": ["A"]},
                ],
            }
        ),
        encoding="utf-8",
    )
    _, components = load_manifest(manifest)
    with pytest.raises(BootstrapManifestError, match="cycle"):
        plan_components(components)


def test_unknown_dependency_is_rejected(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "schema_version": "1.0.0",
                "root": str(tmp_path),
                "components": [
                    {"id": "A", "name": "A", "repository": "x/A", "branch": "feat/a", "local_dir": "A", "depends_on": ["MISSING"]}
                ],
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(BootstrapManifestError, match="unknown dependencies"):
        load_manifest(manifest)
