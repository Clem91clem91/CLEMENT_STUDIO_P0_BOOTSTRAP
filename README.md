# CLEMENT_STUDIO_P0_BOOTSTRAP

Master installer and certification controller for the four CLEMENT STUDIO P0 components.

## Cascade

`P0-01 Skills Hub -> P0-02 Skills MCP -> P0-03 OmniRoute -> P0-04 Dynamic Orchestrator`

P0-03 has no hard dependency on P0-01/P0-02, but the installer keeps a predictable component order. P0-04 requires P0-01, P0-02 and P0-03.

## Guarded installer

`scripts/Install-ClementP0Cascade.ps1` performs:

1. preflight and compatible Python discovery (3.11+);
2. clone missing repositories under `C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS`;
3. fast-forward-only synchronization of clean repositories;
4. protection of an existing divergent/dirty P0-01 checkout instead of resetting it;
5. one `.venv` per P0;
6. editable package install;
7. compile and pytest gates;
8. component certification scripts;
9. Bootstrap self-test and task log under ignored `artifacts/TASK-*`.

The installer contains no `git reset`, forced checkout, merge, tag or force-push path.

## Trusted Odysseus registration

`scripts/Register-P002Odysseus.ps1` registers CLEMENT Skills MCP through Odysseus's local `scripts/odysseus-mcp` CLI. It does not disable authentication, kill processes, restart Odysseus, delete a mismatched existing MCP server or alter security settings.

## Standard install

```powershell
cd "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS\CLEMENT_STUDIO_P0_BOOTSTRAP"
git pull --ff-only origin feat/p0-bootstrap
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Install-ClementP0Cascade.ps1" -Install -Test -Certify
```

## P0-01 materialization

Materialization is opt-in and requires the recovered audit evidence. The installer always executes the importer dry-run before `--apply` and uses the rollback backup root under `Downloads\CLEMENT_P0\P0-01_BACKUPS`.

If the canonical P0-01 checkout is protected because it contains local work or a different branch, materialization is intentionally blocked instead of overwriting it.

## Release gate

No merge, tag or release is performed without explicit user validation.
