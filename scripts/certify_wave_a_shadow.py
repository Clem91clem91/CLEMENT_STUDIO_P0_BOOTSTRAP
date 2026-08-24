from __future__ import annotations

import asyncio
import json
import os
import tempfile
import urllib.request
from pathlib import Path

from clement_agent_runtime.orchestration import RoutedAgentSpec, run_with_fallback
from clement_agent_runtime.runtime import AgentRuntime, OpenAICompatibleTransport
from clement_gpu_manager.gpu import ReservationManager, collect_nvidia_smi
from clement_gpu_manager.scheduler import WorkloadRequest, select_gpu
from clement_knowledge_pipeline.pipeline import KnowledgeRegistry, KnowledgeSource
from clement_knowledge_pipeline.policy import evaluate_ingestion_policy
from clement_memory.store import MemoryRecord, MemoryStore
from clement_omniroute.core import EndpointKind
from clement_omniroute.dynamic_routing import DynamicAgentRouter, ModelCandidate
from clement_omniroute.wave_a import AgentWorkloadProfile, ResourceBudget, build_agent_routing_request
from clement_verified_response.evidence import EvidenceRecord, verify_claim, verify_negative_claim
from clement_verified_response.gate import Verdict, compute_response_verdict


def marker(name: str, value: str) -> None:
    print(f"{name}={value}")


def get_models(base_url: str) -> list[str]:
    with urllib.request.urlopen(f"{base_url.rstrip('/')}/models", timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return [str(item.get("id")) for item in payload.get("data", []) if item.get("id")]


def main() -> int:
    # Memory: machine evidence must override memory, model cannot override machine.
    store = MemoryStore([MemoryRecord("agent_count", 905, "memory")])
    store.put(MemoryRecord("agent_count", 6, "machine_file", evidence_id="TASK_REPORT:E-1"))
    blocked = False
    try:
        store.put(MemoryRecord("agent_count", 905, "model"))
    except ValueError:
        blocked = True
    if store.get("agent_count").value != 6 or not blocked:
        marker("WAVE_A_MEMORY", "FAIL")
        return 1
    marker("WAVE_A_MEMORY", "PASS")

    # Verified Response: deliberately false claim must be rejected while test passes.
    evidence = EvidenceRecord("TASK_REPORT:E-2", "TASK_REPORT", {"agent_count": 6})
    negative = verify_negative_claim(
        name="claim_905_agents",
        forbidden_value=905,
        evidence=evidence,
        source_path="$.agent_count",
    )
    gate = compute_response_verdict([negative])
    if negative.verdict is not Verdict.PASS or gate.verdict is not Verdict.PASS:
        marker("WAVE_A_VERIFIED_RESPONSE", "FAIL")
        return 1
    marker("WAVE_A_VERIFIED_RESPONSE", "PASS")

    # Live GPU telemetry and reservation.
    try:
        snapshot = collect_nvidia_smi()
    except Exception as exc:
        print(f"GPU_ERROR={type(exc).__name__}:{exc}")
        marker("WAVE_A_GPU_LIVE", "INCONCLUSIVE")
        return 2
    if not snapshot.devices:
        marker("WAVE_A_GPU_LIVE", "INCONCLUSIVE")
        return 2
    manager = ReservationManager()
    smallest_probe = min(512, max(1, max(device.memory_free_mb for device in snapshot.devices) // 20))
    decision = select_gpu(
        request=WorkloadRequest("wave-a-probe", "certifier", "AGENT", smallest_probe),
        devices=snapshot.devices,
        reservations=manager,
        safety_margin_mb=256,
    )
    if decision.verdict != "ALLOW" or decision.gpu_index is None:
        print(f"GPU_DECISION={decision}")
        marker("WAVE_A_GPU_LIVE", "FAIL")
        return 1
    marker("WAVE_A_GPU_LIVE", "PASS")
    print(f"WAVE_A_GPU_INDEX={decision.gpu_index}")
    print(f"WAVE_A_GPU_AVAILABLE_MB={decision.available_vram_mb}")

    # OmniRoute consumes the verified GPU budget.
    router = DynamicAgentRouter()
    routing_request = build_agent_routing_request(
        AgentWorkloadProfile(
            "AGENT-WAVE-A",
            required_capabilities=frozenset({"reasoning"}),
            required_context=1024,
            prefer_local=True,
            allow_cloud=False,
        ),
        ResourceBudget(
            available_vram_mb=decision.available_vram_mb,
            max_model_vram_mb=decision.available_vram_mb,
            telemetry_verified=True,
        ),
    )
    candidate = ModelCandidate(
        model_id="wave-a-local-candidate",
        provider_id="lm-studio",
        endpoint_kind=EndpointKind.LOCAL,
        capabilities=frozenset({"reasoning"}),
        quality_score=0.8,
        latency_ms=1000,
        context_limit=8192,
        estimated_vram_mb=0,
        healthy=True,
    )
    route = router.route(routing_request, [candidate])
    if route.verdict != "PASS" or route.primary_model_id != candidate.model_id:
        marker("WAVE_A_OMNIROUTE", "FAIL")
        return 1
    marker("WAVE_A_OMNIROUTE", "PASS")

    # Real model execution via LM Studio OpenAI-compatible endpoint.
    lm_base = os.environ.get("CLEMENT_LM_STUDIO_BASE_URL", "http://127.0.0.1:1234/v1")
    try:
        models = get_models(lm_base)
    except Exception as exc:
        print(f"LM_STUDIO_ERROR={type(exc).__name__}:{exc}")
        marker("WAVE_A_AGENT_RUNTIME_LIVE", "INCONCLUSIVE")
        return 2
    requested_model = os.environ.get("CLEMENT_WAVE_A_MODEL", "").strip()
    model = requested_model if requested_model else (models[0] if models else "")
    if not model or model not in models:
        print(f"LM_STUDIO_MODELS={models}")
        marker("WAVE_A_AGENT_RUNTIME_LIVE", "INCONCLUSIVE")
        return 2
    runtime = AgentRuntime(OpenAICompatibleTransport(base_url=lm_base, provider="lm_studio_local", timeout=90))
    run = asyncio.run(
        run_with_fallback(
            runtime,
            RoutedAgentSpec(
                agent_id="AGENT-WAVE-A",
                role="verifier",
                system_prompt="Return exactly WAVE_A_MODEL_PASS and nothing else.",
                primary_model=model,
            ),
            "Return exactly WAVE_A_MODEL_PASS and nothing else.",
        )
    )
    if run.selected_model is None or run.run.response is None or "WAVE_A_MODEL_PASS" not in run.run.response.text:
        print(f"AGENT_RUN={run}")
        marker("WAVE_A_AGENT_RUNTIME_LIVE", "FAIL")
        return 1
    marker("WAVE_A_AGENT_RUNTIME_LIVE", "PASS")
    print(f"WAVE_A_MODEL={run.selected_model}")

    # Knowledge pipeline: real temporary file bytes, license policy, hashing/dedup.
    registry = KnowledgeRegistry()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "wave_a_memory.txt"
        path.write_text("CLEMENT STUDIO WAVE A knowledge probe", encoding="utf-8")
        source = KnowledgeSource("WAVE-A-KNOWLEDGE", "FILE", str(path), "CC0")
        policy = evaluate_ingestion_policy(source)
        first = registry.ingest_bytes(content=path.read_bytes(), source=source)
        second = registry.ingest_bytes(content=path.read_bytes(), source=source)
    if policy.verdict != "ALLOW" or first.document_id != second.document_id or len(registry.documents()) != 1:
        marker("WAVE_A_KNOWLEDGE", "FAIL")
        return 1
    marker("WAVE_A_KNOWLEDGE", "PASS")

    # End-to-end machine evidence claim on the real model run.
    run_evidence = EvidenceRecord(
        "AGENT_RUNTIME:E-REAL",
        "SYSTEM",
        {"agent": {"state": run.run.state, "model": run.selected_model}},
    )
    state_claim = verify_claim(
        name="agent_runtime_state",
        expected_value="COMPLETED",
        evidence=run_evidence,
        source_path="$.agent.state",
    )
    fake_claim = verify_claim(
        name="fake_model_id",
        expected_value="ABC_FAKE_123",
        evidence=EvidenceRecord("MODEL:E-FAKE", "MODEL", {"id": "ABC_FAKE_123"}),
        source_path="$.id",
    )
    if state_claim.verdict is not Verdict.PASS or fake_claim.verdict is not Verdict.FAIL:
        marker("WAVE_A_FAIL_CLOSED", "FAIL")
        return 1
    marker("WAVE_A_FAIL_CLOSED", "PASS")
    marker("WAVE_A_GLOBAL", "PASS")
    marker("MERGE_EXECUTED", "NO")
    marker("TAG_CREATED", "NO")
    marker("RELEASE_CREATED", "NO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
