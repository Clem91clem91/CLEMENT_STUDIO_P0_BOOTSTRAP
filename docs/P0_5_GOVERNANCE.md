# CLEMENT STUDIO - P0.5 Governance

Status: governance baseline proposed after the certified P0 merge.

This phase changes governance only. It does not create a tag, GitHub Release, production deployment, or package version bump.

## 1. Repositories in scope

- `CLEMENT_STUDIO_SKILLS_HUB`
- `CLEMENT_STUDIO_SKILLS_MCP`
- `CLEMENT_STUDIO_OMNIROUTE`
- `CLEMENT_STUDIO_ORCHESTRATOR`
- `CLEMENT_STUDIO_P0_BOOTSTRAP`

The integration branch is `develop`. The stable/release branch is `main`.

## 2. CI contract

Every repository must expose the same aggregate required check:

- required check: `governance-gate`
- pull requests: `main`, `develop`
- pushes: `main`, `develop`, `feat/**`, `fix/**`, `chore/**`
- manual run: `workflow_dispatch`
- matrix: Windows and Ubuntu, Python 3.11 and 3.13
- concurrency: cancel superseded runs on the same ref

`governance-gate` depends on the complete repository test matrix. Branch protection depends only on this stable aggregate check, not on individual matrix job display names.

## 3. Branch protection policy

### `develop` - enabled during P0.5

Required policy:

- changes enter through a pull request;
- `governance-gate` must pass;
- status checks must be strict/up-to-date with the target branch;
- branch rules apply to administrators;
- stale reviews are dismissed;
- unresolved review conversations block merge;
- force pushes are forbidden;
- branch deletion is forbidden;
- merge commits remain allowed; linear history is not required;
- approval count is `0` because the repositories currently have a single owner and GitHub does not permit an author to approve their own pull request.

The policy is stored in `config/p0_5_governance.json` and can be audited/applied with `scripts/Apply-P05BranchProtection.ps1`.

### `main` - release gate

`main` remains release-only. The same protection can be applied with `-IncludeMain` once the governance CI has been promoted to `main`. No routine feature work targets `main` directly.

## 4. Branch model

- `develop`: integration source of truth for validated development.
- `feat/<topic>`: product capability.
- `fix/<topic>`: non-release corrective change.
- `chore/<topic>`: CI, governance, documentation, maintenance.
- `release/vX.Y.Z`: release preparation only; version/changelog/certification changes.
- `hotfix/vX.Y.Z`: urgent correction starting from `main`, merged back into `develop` after release.

Direct pushes to protected `develop` or protected `main` are not part of the normal workflow.

## 5. Versioning strategy

CLEMENT STUDIO uses Semantic Versioning (`MAJOR.MINOR.PATCH`) per repository.

Current package baseline remains `0.1.0` during P0.5. This governance phase does not change package versions.

Before `1.0.0`:

- PATCH: compatible bug fix or documentation/CI fix that affects a released package state;
- MINOR: new capability or a deliberately breaking pre-1.0 contract change, called out explicitly in the changelog;
- MAJOR `1.0.0`: explicit production graduation only after a dedicated certification and user authorization.

Recommended first coordinated release of the certified P0 baseline: `v0.1.0` in each of the five repositories. It is intentionally not created by P0.5.

## 6. Release process

A release is authorized only by an explicit user instruction. A normal release sequence is:

1. `develop` is green on `governance-gate`.
2. Create `release/vX.Y.Z` from the certified `develop` HEAD.
3. Update `pyproject.toml` version and `CHANGELOG.md` where applicable.
4. Run repository tests and the Bootstrap/global certification appropriate to the phase.
5. Open PR `release/vX.Y.Z -> main`.
6. Require `governance-gate=PASS` and resolved conversations.
7. Merge only after explicit user authorization.
8. Create annotated tag `vX.Y.Z` only after explicit user authorization.
9. Create GitHub Release only after explicit user authorization.
10. Verify release artifacts and then synchronize `main` back into `develop` if needed.

No automated workflow is allowed to create tags or releases merely because a branch was merged.

## 7. Coordinated suite releases

For milestone releases such as the initial P0 baseline, keep the five repository versions aligned when practical. The Bootstrap manifest records the exact certified component HEADs and acts as the suite-level provenance record.

Independent patch releases are allowed later when a component can be updated without changing the public contracts of the other components; the Bootstrap compatibility matrix must then record the supported combination.

## 8. P1 entry criteria

P1 can start when:

- all five P0.5 CI PRs are green;
- `develop` protection is verified on all five repositories;
- the P0.5 governance PRs are merged;
- no tag/release has been created unintentionally;
- the versioning/release policy is retained as the operating contract.

At that point the P0 code baseline is frozen by Git history, CI, branch protection, and the certified Bootstrap provenance.
