# CLEMENT STUDIO — Modular Repository Strategy

## Decision

Large unfinished CLEMENT STUDIO capabilities are developed in separate repositories instead of being added to the Orchestrator monolith.

The Orchestrator remains responsible for coordination contracts. Specialized repositories own their implementation, dependencies, tests and release lifecycle.

## Why separate repositories

1. Blender, Unreal and ComfyUI require very different application integrations and dependencies.
2. GPU telemetry must remain lightweight and independently testable.
3. The verified-response layer must remain deterministic and reusable by every execution domain.
4. Agent runtime and model routing need independent benchmarking without creative-tool dependencies.
5. MONA is an integration product and should depend on stable Blender/Unreal/ComfyUI contracts rather than contain them.
6. Control Center should consume observability APIs instead of importing implementation internals.
7. Knowledge ingestion and social automation have separate security, provenance and provider concerns.

## Repository map

| Order | Repository | Phase | Primary responsibility |
|---:|---|---|---|
| 1 | CLEMENT_STUDIO_MEMORY | P1.1+ | Persistent context and semantic rules, including negative-test semantics |
| 2 | CLEMENT_STUDIO_VERIFIED_RESPONSE | P1.2 | Deterministic claims and final verdict gate |
| 3 | CLEMENT_STUDIO_AGENT_RUNTIME | P1.3 | Real independent model calls and multi-agent execution |
| 4 | CLEMENT_STUDIO_GPU_MANAGER | P1.4 | Live telemetry, resource queues and VRAM arbitration |
| 5 | CLEMENT_STUDIO_KNOWLEDGE_PIPELINE | P1.5 | Drive/web document ingestion with provenance and deduplication |
| 6 | CLEMENT_STUDIO_COMFYUI_STUDIO | P2 | ComfyUI automation |
| 7 | CLEMENT_STUDIO_BLENDER_AUTOPILOT | P2 | Blender automation |
| 8 | CLEMENT_STUDIO_UNREAL_AUTOPILOT | P2 | Unreal automation |
| 9 | CLEMENT_STUDIO_MONA_PIPELINE | P2 | Cross-tool MONA pipeline |
| 10 | CLEMENT_STUDIO_CONTROL_CENTER | P3 | Operational UI/dashboard |
| 11 | CLEMENT_STUDIO_SOCIAL_AUTOMATION | P3 | Social-provider automation contracts |

Dynamic per-agent model selection stays in the existing `CLEMENT_STUDIO_OMNIROUTE` repository because provider routing is already that repository's responsibility.

## Standard repository contract

Each new repository starts with:

- `main` created by GitHub;
- `develop` integration branch;
- `feat/*`, `fix/*`, `chore/*` development branches;
- Python >= 3.11 package scaffold where applicable;
- Windows + Ubuntu CI;
- Python 3.11 + 3.13 matrix;
- required check named `governance-gate`;
- module manifest and roadmap;
- no merge/tag/release performed by the bootstrap.

Branch protection is applied only when explicitly requested and when the GitHub plan/API supports it.

## Delivery waves

### Wave A — Reliability and intelligence

1. Memory v1.1: formalize `CLAIM_VERDICT != TEST_VERDICT` and negative-test semantics.
2. Verified Response Gate: deterministic final verdict object; LLM explanation cannot override it.
3. Agent Runtime: real model invocations, messages, coalitions and verifier passes.
4. OmniRoute extension: per-agent model routing.
5. GPU Manager: live metrics and resource reservations.

### Wave B — Knowledge and creative execution

6. Knowledge Pipeline.
7. ComfyUI Studio.
8. Blender Autopilot.
9. Unreal Autopilot.

### Wave C — Integrated products

10. MONA Pipeline.
11. Control Center.
12. Social Automation.

## Evidence rules

All modules that perform side effects must expose evidence suitable for P1.1/P1.2:

`ACTION -> RAW RESULT -> PROVENANCE -> CONSISTENCY -> VERDICT`

No model-generated value is accepted as machine evidence.

`NO EVIDENCE -> NO PASS`

## Governance

The bootstrap may create repositories, initialize `develop`, push the initial scaffold and optionally configure protection. It must not:

- merge pull requests;
- create tags;
- create releases;
- mutate an already-existing repository automatically.

Existing repositories are reported and skipped so that later work can inspect them before modification.
