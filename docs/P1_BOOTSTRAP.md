# CLEMENT STUDIO — P1 Bootstrap

This bootstrap preserves the P0/P0.5 governance model while certifying the P1 execution layer.

## Pinned implementation

- Repository: `Clem91clem91/CLEMENT_STUDIO_ORCHESTRATOR`
- Branch: `feat/p1-execution-core`
- Head: `6329530b787a59c13be9654e189a31a4501dab46`

## P1 gates

The Shadow certification must prove:

- `P1_01=PASS`
- `P1_02=PASS`
- `P1_03=PASS`
- `P1_04=PASS`
- `EXECUTION_FABRIC=PASS`
- `AGENT_RUNTIME=PASS`
- `RESOURCE_GUARD=PASS`
- `OBSERVABILITY=PASS`
- `SHADOW_REAL_E2E=PASS`
- `GLOBAL_P1=PASS`

## Real E2E scope

The Orchestrator certification opens enabled Odysseus MCP servers, discovers their real tool catalogs, then requires automatic capability selection for Windows file write/read, Files Plus move, PowerShell execution, Google Drive upload and verification. It also proves dynamic agents, coalition promotion, resource/security decisions and TASK report generation.

## Governance

This bootstrap never performs merge, tag or release. Those operations remain separately authorized. The P1 PRs remain Draft until Shadow certification is PASS and the user explicitly authorizes merge.
