from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "p0_5_governance.json"
SCRIPT = ROOT / "scripts" / "Apply-P05BranchProtection.ps1"
DOC = ROOT / "docs" / "P0_5_GOVERNANCE.md"

EXPECTED_REPOSITORIES = [
    "CLEMENT_STUDIO_SKILLS_HUB",
    "CLEMENT_STUDIO_SKILLS_MCP",
    "CLEMENT_STUDIO_OMNIROUTE",
    "CLEMENT_STUDIO_ORCHESTRATOR",
    "CLEMENT_STUDIO_P0_BOOTSTRAP",
]


def test_governance_manifest_is_fail_closed() -> None:
    payload = json.loads(CONFIG.read_text(encoding="utf-8"))
    assert payload["phase"] == "P0.5"
    assert payload["target_branch"] == "develop"
    assert payload["required_status_check"] == "governance-gate"
    assert payload["repositories"] == EXPECTED_REPOSITORIES

    protection = payload["branch_protection"]
    assert protection["require_pull_request"] is True
    assert protection["required_approving_review_count"] == 0
    assert protection["strict_status_checks"] is True
    assert protection["enforce_admins"] is True
    assert protection["required_conversation_resolution"] is True
    assert protection["allow_force_pushes"] is False
    assert protection["allow_deletions"] is False
    assert protection["required_linear_history"] is False


def test_release_policy_does_not_auto_release() -> None:
    payload = json.loads(CONFIG.read_text(encoding="utf-8"))
    versioning = payload["versioning"]
    assert versioning["scheme"] == "SemVer"
    assert versioning["current_baseline"] == "0.1.0"
    assert versioning["tag_format"] == "vMAJOR.MINOR.PATCH"
    assert versioning["tag_or_release_requires_explicit_user_authorization"] is True


def test_branch_protection_runner_has_dry_run_and_apply_modes() -> None:
    text = SCRIPT.read_text(encoding="utf-8")
    assert "[switch]$Apply" in text
    assert '"--method", "PUT"' in text
    assert "branches/$Branch/protection" in text
    assert "P0_5_BRANCH_PROTECTION_VERIFIED" in text
    assert "dismissal_restrictions =" not in text
    assert "bypass_pull_request_allowances =" not in text
    assert "TAG_CREATED=NO" in text
    assert "RELEASE_CREATED=NO" in text
    assert "/releases" not in text.lower()
    assert "/git/tags" not in text.lower()


def test_governance_document_is_versioned() -> None:
    text = DOC.read_text(encoding="utf-8")
    assert "governance-gate" in text
    assert "release/vX.Y.Z" in text
    assert "v0.1.0" in text
    assert "No automated workflow is allowed to create tags or releases" in text
