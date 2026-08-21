from __future__ import annotations

import asyncio
import json
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True, slots=True)
class ModelRequest:
    model: str
    messages: tuple[dict[str, str], ...]
    temperature: float = 0.2
    max_tokens: int | None = None


@dataclass(frozen=True, slots=True)
class ModelResponse:
    text: str
    model: str
    provider: str
    technical_tokens: int = 0
    raw: dict[str, Any] = field(default_factory=dict)


class ModelTransport(Protocol):
    async def complete(self, request: ModelRequest) -> ModelResponse: ...


@dataclass(frozen=True, slots=True)
class AgentSpec:
    agent_id: str
    role: str
    model: str
    system_prompt: str


@dataclass(frozen=True, slots=True)
class AgentRun:
    agent_id: str
    state: str
    response: ModelResponse | None
    error: str | None = None


class AgentRuntime:
    def __init__(self, transport: ModelTransport) -> None:
        self.transport = transport

    async def run_agent(self, spec: AgentSpec, prompt: str) -> AgentRun:
        request = ModelRequest(
            model=spec.model,
            messages=(
                {"role": "system", "content": spec.system_prompt},
                {"role": "user", "content": prompt},
            ),
        )
        try:
            response = await self.transport.complete(request)
        except Exception as exc:  # transport boundary
            return AgentRun(spec.agent_id, "FAILED", None, f"{type(exc).__name__}:{exc}")
        return AgentRun(spec.agent_id, "COMPLETED", response)

    async def run_coalition(self, specs: list[AgentSpec], prompt: str) -> list[AgentRun]:
        if len({item.agent_id for item in specs}) != len(specs):
            raise ValueError("DUPLICATE_AGENT_ID")
        return list(await asyncio.gather(*(self.run_agent(spec, prompt) for spec in specs)))


class OpenAICompatibleTransport:
    """Minimal transport for LM Studio, OmniRoute or other OpenAI-compatible endpoints."""

    def __init__(self, *, base_url: str, provider: str, api_key: str | None = None, timeout: float = 120.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.provider = provider
        self.api_key = api_key
        self.timeout = float(timeout)

    async def complete(self, request: ModelRequest) -> ModelResponse:
        return await asyncio.to_thread(self._complete_sync, request)

    def _complete_sync(self, request: ModelRequest) -> ModelResponse:
        body: dict[str, Any] = {
            "model": request.model,
            "messages": list(request.messages),
            "temperature": request.temperature,
        }
        if request.max_tokens is not None:
            body["max_tokens"] = int(request.max_tokens)
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        http_request = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(body).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(http_request, timeout=self.timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
        choices = payload.get("choices") or []
        if not choices:
            raise RuntimeError("MODEL_RESPONSE_CHOICES_EMPTY")
        text = str((choices[0].get("message") or {}).get("content") or "")
        usage = payload.get("usage") or {}
        tokens = int(usage.get("total_tokens") or 0)
        return ModelResponse(
            text=text,
            model=str(payload.get("model") or request.model),
            provider=self.provider,
            technical_tokens=tokens,
            raw=payload,
        )
