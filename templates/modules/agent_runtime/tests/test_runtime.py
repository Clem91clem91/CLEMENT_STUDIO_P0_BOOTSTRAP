import asyncio

from clement_agent_runtime.runtime import AgentRuntime, AgentSpec, ModelRequest, ModelResponse


class FakeTransport:
    async def complete(self, request: ModelRequest) -> ModelResponse:
        return ModelResponse(
            text=f"done:{request.model}",
            model=request.model,
            provider="fake",
            technical_tokens=12,
            raw={"ok": True},
        )


class FailingTransport:
    async def complete(self, request: ModelRequest) -> ModelResponse:
        raise RuntimeError("offline")


def test_agent_executes_real_transport_boundary() -> None:
    runtime = AgentRuntime(FakeTransport())
    spec = AgentSpec("AGENT-1", "planner", "qwen", "Plan carefully")
    run = asyncio.run(runtime.run_agent(spec, "mission"))
    assert run.state == "COMPLETED"
    assert run.response is not None
    assert run.response.text == "done:qwen"


def test_coalition_executes_multiple_agent_calls() -> None:
    runtime = AgentRuntime(FakeTransport())
    specs = [
        AgentSpec("AGENT-1", "planner", "qwen", "plan"),
        AgentSpec("AGENT-2", "verifier", "verify-model", "verify"),
    ]
    runs = asyncio.run(runtime.run_coalition(specs, "mission"))
    assert [run.agent_id for run in runs] == ["AGENT-1", "AGENT-2"]
    assert all(run.state == "COMPLETED" for run in runs)


def test_transport_failure_is_not_reported_as_completed() -> None:
    runtime = AgentRuntime(FailingTransport())
    spec = AgentSpec("AGENT-X", "general", "model", "system")
    run = asyncio.run(runtime.run_agent(spec, "mission"))
    assert run.state == "FAILED"
    assert run.response is None
    assert "RuntimeError:offline" == run.error
