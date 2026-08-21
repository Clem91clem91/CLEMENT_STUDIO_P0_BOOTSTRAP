from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "module_repositories.json"
SCRIPT = ROOT / "scripts" / "New-ClementStudioModuleRepos.ps1"

EXPECTED_REPOS = {
    "CLEMENT_STUDIO_MEMORY",
    "CLEMENT_STUDIO_VERIFIED_RESPONSE",
    "CLEMENT_STUDIO_AGENT_RUNTIME",
    "CLEMENT_STUDIO_GPU_MANAGER",
    "CLEMENT_STUDIO_KNOWLEDGE_PIPELINE",
    "CLEMENT_STUDIO_COMFYUI_STUDIO",
    "CLEMENT_STUDIO_BLENDER_AUTOPILOT",
    "CLEMENT_STUDIO_UNREAL_AUTOPILOT",
    "CLEMENT_STUDIO_MONA_PIPELINE",
    "CLEMENT_STUDIO_CONTROL_CENTER",
    "CLEMENT_STUDIO_SOCIAL_AUTOMATION",
}


def test_module_manifest_is_complete_and_ordered() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    modules = data["modules"]
    assert len(modules) == 11
    assert {item["repository"] for item in modules} == EXPECTED_REPOS
    assert [item["order"] for item in modules] == list(range(1, 12))
    assert len({item["key"] for item in modules}) == len(modules)
    assert len({item["package"] for item in modules}) == len(modules)
    assert data["governance"]["no_merge_without_user_approval"] is True
    assert data["governance"]["no_tag_without_user_approval"] is True
    assert data["governance"]["no_release_without_user_approval"] is True


def test_omniroute_extension_stays_in_existing_repo() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    extensions = data["existing_repository_extensions"]
    assert extensions == [
        {
            "repository": "CLEMENT_STUDIO_OMNIROUTE",
            "workstream": "dynamic-agent-model-routing",
            "description": "Per-agent model selection using capability, quality, latency, locality, cost, context and resource signals.",
        }
    ]


def test_repository_bootstrap_is_non_merging_and_non_releasing() -> None:
    text = SCRIPT.read_text(encoding="utf-8-sig")
    lowered = text.lower()
    assert "gh repo create" not in lowered  # invocation is argument-array based, avoiding shell interpolation
    assert '"repo", "create"' in text
    assert "MERGE_EXECUTED=NO" in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text
    assert "gh pr merge" not in lowered
    assert "gh release create" not in lowered
    assert "git tag " not in lowered
    assert "git add ." not in lowered
    assert "git add -a" not in lowered


def test_existing_repositories_are_fail_safe() -> None:
    text = SCRIPT.read_text(encoding="utf-8-sig")
    assert "MUTATION=SKIPPED_EXISTING_REPOSITORY" in text
    assert "LOCAL_PATH_ALREADY_EXISTS_FOR_NEW_REPO" in text
    assert "DRY_RUN" in text
