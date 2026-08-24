& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $Owner = "Clem91clem91"
    $ToolsRoot = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS"
    $OdysseusPython = "C:\Users\Shadow\ODYSSEUS\venv\Scripts\python.exe"

    Write-Host "============================================================"
    Write-Host "CLEMENT STUDIO - COGNITIVE CORE PRODUCTION"
    Write-Host "MODE=GITHUB_FIRST"
    Write-Host "MERGE_ALLOWED=NO"
    Write-Host "TAG_ALLOWED=NO"
    Write-Host "RELEASE_ALLOWED=NO"
    Write-Host "============================================================"

    foreach ($Command in @("git", "gh")) {
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw "COMMAND_NOT_FOUND=$Command"
        }
    }

    if (-not (Test-Path -LiteralPath $OdysseusPython -PathType Leaf)) {
        throw "ODYSSEUS_PYTHON_NOT_FOUND=$OdysseusPython"
    }

    gh auth status
    if ($LASTEXITCODE -ne 0) { throw "GH_AUTH=FAIL" }

    New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null
    $Utf8 = New-Object System.Text.UTF8Encoding($false)

    function Write-TextFile {
        param([string]$Path, [string]$Content)
        $Parent = Split-Path -Parent $Path
        if ($Parent) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($Path, $Content, $Utf8)
    }

    function Invoke-Git {
        param([string]$RepoPath, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
        & git -C $RepoPath @Args
        if ($LASTEXITCODE -ne 0) { throw "GIT_FAILED=$($Args -join ' ') REPO=$RepoPath" }
    }

    function Remote-RepoExists {
        param([string]$FullName)
        & gh repo view $FullName --json name 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
    }

    function Remote-BranchExists {
        param([string]$FullName, [string]$Branch)
        & gh api "repos/$FullName/branches/$Branch" 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
    }

    function Initialize-Repository {
        param(
            [string]$Name,
            [string]$Description,
            [string]$FeatureBranch
        )

        $FullName = "$Owner/$Name"
        $RepoPath = Join-Path $ToolsRoot $Name

        Write-Host ""
        Write-Host "=== REPOSITORY_PREPARE=$Name ==="

        $RemoteExists = Remote-RepoExists $FullName
        Write-Host "REMOTE_EXISTS=$RemoteExists"

        if (-not $RemoteExists) {
            gh repo create $FullName --private --description $Description
            if ($LASTEXITCODE -ne 0) { throw "REPO_CREATE_FAILED=$FullName" }
            Write-Host "REPOSITORY_CREATED=$FullName"
        }

        if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
            if ($RemoteExists) {
                gh repo clone $FullName $RepoPath
                if ($LASTEXITCODE -ne 0) { throw "REPO_CLONE_FAILED=$FullName" }
            }
            else {
                New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null
                & git -C $RepoPath init -b main
                if ($LASTEXITCODE -ne 0) { throw "GIT_INIT_FAILED=$Name" }
                & git -C $RepoPath remote add origin "https://github.com/$FullName.git"
                if ($LASTEXITCODE -ne 0) { throw "REMOTE_ADD_FAILED=$Name" }

                Write-TextFile (Join-Path $RepoPath "README.md") "# $Name`r`n`r`nCLEMENT STUDIO cognitive foundation repository.`r`n"
                Invoke-Git $RepoPath add README.md
                & git -C $RepoPath commit -m "chore: initialize repository"
                if ($LASTEXITCODE -ne 0) { throw "INITIAL_COMMIT_FAILED=$Name" }
                Invoke-Git $RepoPath push -u origin main
            }
        }

        if (-not (Test-Path -LiteralPath (Join-Path $RepoPath ".git") -PathType Container)) {
            throw "LOCAL_NOT_GIT_REPO=$RepoPath"
        }

        Invoke-Git $RepoPath fetch origin --prune

        $Dirty = @(& git -C $RepoPath status --porcelain)
        if ($Dirty.Count -gt 0) {
            Write-Host "DIRTY_BEGIN=$Name"
            $Dirty | ForEach-Object { Write-Host $_ }
            Write-Host "DIRTY_END=$Name"
            throw "LOCAL_WORKTREE_DIRTY=$Name"
        }

        if (Remote-BranchExists $FullName "develop") {
            & git -C $RepoPath switch develop 2>$null
            if ($LASTEXITCODE -ne 0) {
                Invoke-Git $RepoPath switch -c develop --track origin/develop
            }
            Invoke-Git $RepoPath pull --ff-only origin develop
        }
        else {
            & git -C $RepoPath switch main
            if ($LASTEXITCODE -ne 0) { throw "SWITCH_MAIN_FAILED=$Name" }
            Invoke-Git $RepoPath pull --ff-only origin main
            Invoke-Git $RepoPath switch -c develop
            Invoke-Git $RepoPath push -u origin develop
        }

        if (Remote-BranchExists $FullName $FeatureBranch) {
            & git -C $RepoPath switch $FeatureBranch 2>$null
            if ($LASTEXITCODE -ne 0) {
                Invoke-Git $RepoPath switch -c $FeatureBranch --track "origin/$FeatureBranch"
            }
            Invoke-Git $RepoPath pull --ff-only origin $FeatureBranch
        }
        else {
            & git -C $RepoPath switch develop
            if ($LASTEXITCODE -ne 0) { throw "SWITCH_DEVELOP_FAILED=$Name" }
            Invoke-Git $RepoPath switch -c $FeatureBranch
        }

        return $RepoPath
    }

    function Write-CommonFiles {
        param(
            [string]$RepoPath,
            [string]$ProjectName,
            [string]$PackageName,
            [string]$Description
        )

        $PyProject = @"
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "$ProjectName"
version = "0.1.0"
description = "$Description"
requires-python = ">=3.11"

[project.optional-dependencies]
dev = ["pytest>=8"]

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["src"]
"@

        Write-TextFile (Join-Path $RepoPath "pyproject.toml") $PyProject
        Write-TextFile (Join-Path $RepoPath ".gitignore") @'
__pycache__/
*.py[cod]
.pytest_cache/
.venv/
venv/
*.egg-info/
build/
dist/
.env
*.log
'@

        Write-TextFile (Join-Path $RepoPath ".github\workflows\ci.yml") @'
name: module-ci

on:
  workflow_dispatch:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop, "feat/**", "fix/**", "chore/**"]

permissions:
  contents: read

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
        python-version: ["3.11", "3.13"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - run: python -m pip install --upgrade pip
      - run: python -m pip install -e ".[dev]"
      - run: python -m compileall -q src
      - run: python -m pytest -q

  governance-gate:
    if: always()
    needs: [test]
    runs-on: ubuntu-latest
    steps:
      - name: Fail closed
        shell: bash
        run: |
          test "${{ needs.test.result }}" = "success"
'@

        New-Item -ItemType Directory -Path (Join-Path $RepoPath "src\$PackageName") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $RepoPath "tests") -Force | Out-Null
    }

    function Build-CoreRepo {
        param([string]$RepoPath)

        Write-CommonFiles $RepoPath "clement-studio-core" "clement_core" "CLEMENT STUDIO cognitive contracts, event bus, provenance and runtime adapters."

        Write-TextFile (Join-Path $RepoPath "README.md") @'
# CLEMENT_STUDIO_CORE

Stable cognitive contracts for CLEMENT STUDIO.

Initial MVP:
- shared risk/operation/capability contracts;
- Event Bus;
- provenance records;
- context packets;
- Integration Decision Engine (`KEEP/ADAPT/FORK/REIMPLEMENT/REJECT`);
- read-only Odysseus runtime adapter.

Odysseus is an execution/runtime adapter, not the owner of CLEMENT memory or knowledge.
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\__init__.py") @'
from .contracts import OperationKind, RiskLevel, CapabilityRequest
from .events import EventBus, EventEnvelope, EventType
from .integration import IntegrationDecision, IntegrationDecisionRecord
from .provenance import EvidenceRef, ProvenanceRecord
from .context import ContextPacket

__all__ = [
    "OperationKind", "RiskLevel", "CapabilityRequest",
    "EventBus", "EventEnvelope", "EventType",
    "IntegrationDecision", "IntegrationDecisionRecord",
    "EvidenceRef", "ProvenanceRecord", "ContextPacket",
]
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\contracts.py") @'
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum


class RiskLevel(str, Enum):
    SAFE = "SAFE"
    SENSITIVE = "SENSITIVE"
    DESTRUCTIVE = "DESTRUCTIVE"


class OperationKind(str, Enum):
    READ = "READ"
    WRITE = "WRITE"
    EXECUTE = "EXECUTE"
    DELETE = "DELETE"
    EXTERNAL_PUBLISH = "EXTERNAL_PUBLISH"


@dataclass(frozen=True)
class CapabilityRequest:
    capability: str
    operation: OperationKind = OperationKind.READ
    risk: RiskLevel = RiskLevel.SAFE
    constraints: tuple[str, ...] = ()
    metadata: dict[str, object] = field(default_factory=dict)
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\events.py") @'
from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Callable
from uuid import uuid4


class EventType(str, Enum):
    FILE_CREATED = "FILE_CREATED"
    FILE_MODIFIED = "FILE_MODIFIED"
    MEMORY_CREATED = "MEMORY_CREATED"
    MEMORY_SUPERSEDED = "MEMORY_SUPERSEDED"
    ENTITY_CREATED = "ENTITY_CREATED"
    RELATION_CREATED = "RELATION_CREATED"
    AGENT_STARTED = "AGENT_STARTED"
    AGENT_FINISHED = "AGENT_FINISHED"
    MODEL_CALLED = "MODEL_CALLED"
    MCP_CALLED = "MCP_CALLED"
    GIT_COMMIT_CREATED = "GIT_COMMIT_CREATED"
    TEST_FAILED = "TEST_FAILED"
    TEST_PASSED = "TEST_PASSED"
    OSINT_EVENT_DETECTED = "OSINT_EVENT_DETECTED"


@dataclass(frozen=True)
class EventEnvelope:
    event_type: EventType
    payload: dict[str, object] = field(default_factory=dict)
    actor: str | None = None
    task_id: str | None = None
    entity_ids: tuple[str, ...] = ()
    source: str | None = None
    event_id: str = field(default_factory=lambda: str(uuid4()))
    occurred_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class EventBus:
    def __init__(self) -> None:
        self._history: list[EventEnvelope] = []
        self._subscribers: list[Callable[[EventEnvelope], None]] = []

    def subscribe(self, handler: Callable[[EventEnvelope], None]) -> None:
        if handler not in self._subscribers:
            self._subscribers.append(handler)

    def publish(self, event: EventEnvelope) -> EventEnvelope:
        self._history.append(event)
        for handler in tuple(self._subscribers):
            handler(event)
        return event

    def history(self, *, event_type: EventType | None = None) -> tuple[EventEnvelope, ...]:
        if event_type is None:
            return tuple(self._history)
        return tuple(event for event in self._history if event.event_type == event_type)
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\provenance.py") @'
from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass(frozen=True)
class EvidenceRef:
    source_type: str
    source_reference: str
    sha256: str | None = None
    observed_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    confidence: float = 1.0

    def __post_init__(self) -> None:
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError("confidence must be between 0 and 1")


@dataclass(frozen=True)
class ProvenanceRecord:
    claim_id: str
    evidence: tuple[EvidenceRef, ...]
    verified: bool = False
    notes: str | None = None
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\context.py") @'
from __future__ import annotations
from dataclasses import dataclass, field


@dataclass(frozen=True)
class ContextPacket:
    objective: str
    user_context: dict[str, object] = field(default_factory=dict)
    memory_refs: tuple[str, ...] = ()
    knowledge_refs: tuple[str, ...] = ()
    constraints: tuple[str, ...] = ()
    capability_ids: tuple[str, ...] = ()
    task_id: str | None = None
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\integration.py") @'
from __future__ import annotations
from dataclasses import dataclass
from enum import Enum


class IntegrationDecision(str, Enum):
    KEEP = "KEEP"
    ADAPT = "ADAPT"
    FORK = "FORK"
    REIMPLEMENT = "REIMPLEMENT"
    REJECT = "REJECT"


@dataclass(frozen=True)
class IntegrationDecisionRecord:
    technology: str
    decision: IntegrationDecision
    rationale: str
    required_contract: str | None = None
    reversible: bool = True
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\runtime_adapters\__init__.py") @'
from .odysseus import OdysseusAdapterConfig, OdysseusRuntimeAdapter

__all__ = ["OdysseusAdapterConfig", "OdysseusRuntimeAdapter"]
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_core\runtime_adapters\odysseus.py") @'
from __future__ import annotations
import json
import urllib.request
from dataclasses import dataclass


@dataclass(frozen=True)
class OdysseusAdapterConfig:
    base_url: str = "http://127.0.0.1:7000"
    omniroute_url: str = "http://127.0.0.1:20128/v1"
    timeout: float = 5.0


class OdysseusRuntimeAdapter:
    """Read-only first adapter. No source/database mutation is performed."""

    def __init__(self, config: OdysseusAdapterConfig | None = None) -> None:
        self.config = config or OdysseusAdapterConfig()

    def health(self) -> dict[str, object]:
        request = urllib.request.Request(self.config.base_url.rstrip("/") + "/health")
        with urllib.request.urlopen(request, timeout=self.config.timeout) as response:
            raw = response.read().decode("utf-8", errors="replace")
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                payload = {"raw": raw}
            return {"http_status": response.status, "payload": payload}

    def model_router(self) -> dict[str, str]:
        return {"kind": "PROXY", "base_url": self.config.omniroute_url}
'@

        Write-TextFile (Join-Path $RepoPath "tests\test_core.py") @'
from clement_core import (
    CapabilityRequest, EventBus, EventEnvelope, EventType,
    IntegrationDecision, IntegrationDecisionRecord,
    OperationKind, RiskLevel,
)


def test_event_bus_records_and_dispatches():
    bus = EventBus()
    received = []
    bus.subscribe(received.append)
    event = EventEnvelope(EventType.TEST_PASSED, {"suite": "core"})
    bus.publish(event)
    assert bus.history() == (event,)
    assert received == [event]


def test_capability_contract_separates_operation_and_risk():
    request = CapabilityRequest("repository.read", OperationKind.READ, RiskLevel.SAFE)
    assert request.operation is OperationKind.READ
    assert request.risk is RiskLevel.SAFE


def test_integration_decision_engine_contract():
    record = IntegrationDecisionRecord("Graphiti", IntegrationDecision.ADAPT, "Use behind CLEMENT API")
    assert record.reversible is True
    assert record.decision.value == "ADAPT"
'@
    }

    function Build-IntentRepo {
        param([string]$RepoPath)

        Write-CommonFiles $RepoPath "clement-studio-intent" "clement_intent" "CLEMENT STUDIO deterministic Intent Compiler MVP."

        Write-TextFile (Join-Path $RepoPath "README.md") @'
# CLEMENT_STUDIO_INTENT

Intent Core MVP. Converts natural-language objectives into a stable machine contract containing objective, capabilities, constraints, risk and expected result. Initial compiler is deterministic and dependency-free so it can be verified before adding LLM-assisted compilation.
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_intent\__init__.py") @'
from .contracts import CompiledIntent, IntentRisk
from .compiler import IntentCompiler

__all__ = ["CompiledIntent", "IntentRisk", "IntentCompiler"]
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_intent\contracts.py") @'
from __future__ import annotations
from dataclasses import dataclass
from enum import Enum


class IntentRisk(str, Enum):
    SAFE = "SAFE"
    SENSITIVE = "SENSITIVE"
    DESTRUCTIVE = "DESTRUCTIVE"


@dataclass(frozen=True)
class CompiledIntent:
    objective: str
    intent: str
    constraints: tuple[str, ...]
    required_capabilities: tuple[str, ...]
    risk: IntentRisk
    expected_result: tuple[str, ...]
    source_text: str
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_intent\compiler.py") @'
from __future__ import annotations
from .contracts import CompiledIntent, IntentRisk


class IntentCompiler:
    CAPABILITY_RULES = {
        "github": "repository",
        "repo": "repository",
        "code": "code",
        "script": "code",
        "powershell": "filesystem.execute",
        "fichier": "filesystem",
        "file": "filesystem",
        "test": "testing",
        "vérif": "verification",
        "verif": "verification",
        "drive": "drive",
        "mcp": "mcp",
    }
    DESTRUCTIVE_WORDS = ("supprime", "delete", "efface", "purge", "destroy")
    SENSITIVE_WORDS = ("corrige", "repair", "execute", "exécute", "écrit", "write", "push", "publish")

    def compile(self, text: str, *, constraints: tuple[str, ...] = ()) -> CompiledIntent:
        source = (text or "").strip()
        if not source:
            raise ValueError("intent text is empty")
        lower = source.lower()
        capabilities = sorted({cap for token, cap in self.CAPABILITY_RULES.items() if token in lower})
        if any(word in lower for word in self.DESTRUCTIVE_WORDS):
            risk = IntentRisk.DESTRUCTIVE
        elif any(word in lower for word in self.SENSITIVE_WORDS):
            risk = IntentRisk.SENSITIVE
        else:
            risk = IntentRisk.SAFE
        if "corrig" in lower or "repair" in lower:
            intent = "diagnose_and_repair"
            expected = ("diagnosed", "repaired", "tested", "evidence_supplied")
        elif "cré" in lower or "create" in lower or "build" in lower:
            intent = "create"
            expected = ("created", "tested", "evidence_supplied")
        else:
            intent = "execute_objective"
            expected = ("completed", "verified")
        return CompiledIntent(
            objective=source,
            intent=intent,
            constraints=tuple(constraints),
            required_capabilities=tuple(capabilities),
            risk=risk,
            expected_result=expected,
            source_text=source,
        )
'@

        Write-TextFile (Join-Path $RepoPath "tests\test_intent.py") @'
from clement_intent import IntentCompiler, IntentRisk


def test_compiles_repair_request():
    result = IntentCompiler().compile(
        "Regarde pourquoi mon code GitHub ne marche plus, corrige et teste",
        constraints=("Windows 11", "PowerShell"),
    )
    assert result.intent == "diagnose_and_repair"
    assert "repository" in result.required_capabilities
    assert "code" in result.required_capabilities
    assert "testing" in result.required_capabilities
    assert result.risk is IntentRisk.SENSITIVE
    assert result.constraints == ("Windows 11", "PowerShell")


def test_delete_is_destructive():
    result = IntentCompiler().compile("Supprime ce fichier")
    assert result.risk is IntentRisk.DESTRUCTIVE
'@
    }

    function Build-KnowledgeRepo {
        param([string]$RepoPath)

        Write-CommonFiles $RepoPath "clement-studio-knowledge" "clement_knowledge" "CLEMENT STUDIO ontology, entity resolution, temporal graph and Digital Twin primitives."

        Write-TextFile (Join-Path $RepoPath "README.md") @'
# CLEMENT_STUDIO_KNOWLEDGE

Knowledge Core MVP.

Memory answers what CLEMENT should remember. Knowledge represents what exists, how entities are related, when relationships are valid, and why a fact is trusted.

This MVP deliberately uses an in-memory deterministic store. Graph databases remain replaceable adapters evaluated later by the Integration Decision Engine.
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_knowledge\__init__.py") @'
from .models import Entity, Relation, RelationStatus
from .ontology import CORE_ENTITY_TYPES, CORE_RELATION_TYPES
from .store import KnowledgeStore, normalize_alias

__all__ = [
    "Entity", "Relation", "RelationStatus",
    "CORE_ENTITY_TYPES", "CORE_RELATION_TYPES",
    "KnowledgeStore", "normalize_alias",
]
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_knowledge\ontology.py") @'
CORE_ENTITY_TYPES = frozenset({
    "Person", "Organization", "Project", "Repository", "File", "Document",
    "Application", "Machine", "Service", "MCP", "Agent", "Skill", "Model",
    "Provider", "Task", "Decision", "Event", "Location", "Asset", "Dataset",
    "API", "Issue", "Commit", "PullRequest", "Release",
})

CORE_RELATION_TYPES = frozenset({
    "OWNS", "CONTAINS", "DEPENDS_ON", "USES", "CREATED_BY", "MODIFIED_BY",
    "RUNS_ON", "CONNECTED_TO", "DERIVED_FROM", "MENTIONS", "LOCATED_AT",
    "EXECUTED_BY", "VALIDATED_BY", "SUPERSEDES", "FAILED_BECAUSE", "RELATED_TO",
})
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_knowledge\models.py") @'
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum


class RelationStatus(str, Enum):
    ACTIVE = "ACTIVE"
    SUPERSEDED = "SUPERSEDED"
    ARCHIVED = "ARCHIVED"
    UNCERTAIN = "UNCERTAIN"


@dataclass(frozen=True)
class Entity:
    entity_id: str
    entity_type: str
    canonical_name: str
    aliases: tuple[str, ...] = ()
    attributes: dict[str, object] = field(default_factory=dict)
    provenance_refs: tuple[str, ...] = ()


@dataclass(frozen=True)
class Relation:
    relation_id: str
    source_id: str
    relation_type: str
    target_id: str
    status: RelationStatus = RelationStatus.ACTIVE
    valid_from: str | None = None
    valid_until: str | None = None
    confidence: float = 1.0
    provenance_refs: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError("confidence must be between 0 and 1")
'@

        Write-TextFile (Join-Path $RepoPath "src\clement_knowledge\store.py") @'
from __future__ import annotations
import re
from dataclasses import replace
from .models import Entity, Relation, RelationStatus
from .ontology import CORE_ENTITY_TYPES, CORE_RELATION_TYPES


def normalize_alias(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").lower())


class KnowledgeStore:
    def __init__(self) -> None:
        self._entities: dict[str, Entity] = {}
        self._aliases: dict[str, str] = {}
        self._relations: dict[str, Relation] = {}

    def put_entity(self, entity: Entity) -> Entity:
        if entity.entity_type not in CORE_ENTITY_TYPES:
            raise ValueError(f"unsupported entity type: {entity.entity_type}")
        names = (entity.canonical_name, *entity.aliases)
        for name in names:
            key = normalize_alias(name)
            existing = self._aliases.get(key)
            if existing is not None and existing != entity.entity_id:
                raise ValueError(f"alias conflict: {name}")
        self._entities[entity.entity_id] = entity
        for name in names:
            self._aliases[normalize_alias(name)] = entity.entity_id
        return entity

    def resolve(self, value: str) -> Entity | None:
        entity_id = self._aliases.get(normalize_alias(value))
        return self._entities.get(entity_id) if entity_id else None

    def get_entity(self, entity_id: str) -> Entity | None:
        return self._entities.get(entity_id)

    def put_relation(self, relation: Relation) -> Relation:
        if relation.relation_type not in CORE_RELATION_TYPES:
            raise ValueError(f"unsupported relation type: {relation.relation_type}")
        if relation.source_id not in self._entities or relation.target_id not in self._entities:
            raise KeyError("relation endpoints must exist")
        self._relations[relation.relation_id] = relation
        return relation

    def supersede_relation(self, relation_id: str, *, valid_until: str) -> Relation:
        current = self._relations[relation_id]
        updated = replace(current, status=RelationStatus.SUPERSEDED, valid_until=valid_until)
        self._relations[relation_id] = updated
        return updated

    def relations_for(self, entity_id: str, *, active_only: bool = True) -> tuple[Relation, ...]:
        result = [r for r in self._relations.values() if r.source_id == entity_id or r.target_id == entity_id]
        if active_only:
            result = [r for r in result if r.status is RelationStatus.ACTIVE]
        return tuple(result)
'@

        Write-TextFile (Join-Path $RepoPath "tests\test_knowledge.py") @'
import pytest
from clement_knowledge import Entity, KnowledgeStore, Relation, RelationStatus


def test_entity_resolution_collapses_aliases():
    store = KnowledgeStore()
    repo = Entity(
        "repo_00031", "Repository", "CLEMENT_STUDIO_MCP_HUB",
        aliases=("Clement MCP Hub", "CLEMENT-STUDIO-MCP-HUB", "github.com/Clem91clem91/CLEMENT_STUDIO_MCP_HUB"),
    )
    store.put_entity(repo)
    assert store.resolve("Clement MCP Hub").entity_id == "repo_00031"
    assert store.resolve("CLEMENT-STUDIO-MCP-HUB").entity_id == "repo_00031"


def test_temporal_relation_can_be_superseded():
    store = KnowledgeStore()
    store.put_entity(Entity("p0", "Project", "P0"))
    store.put_entity(Entity("github", "Service", "GitHub"))
    store.put_relation(Relation("rel1", "p0", "USES", "github", valid_from="2026-08-20"))
    updated = store.supersede_relation("rel1", valid_until="2026-08-24")
    assert updated.status is RelationStatus.SUPERSEDED
    assert store.relations_for("p0") == ()
    assert store.relations_for("p0", active_only=False) == (updated,)


def test_alias_conflict_fails_closed():
    store = KnowledgeStore()
    store.put_entity(Entity("a", "Repository", "Repo A", aliases=("shared",)))
    with pytest.raises(ValueError):
        store.put_entity(Entity("b", "Repository", "Repo B", aliases=("shared",)))
'@
    }

    $Specs = @(
        @{ Name="CLEMENT_STUDIO_CORE"; Description="CLEMENT cognitive contracts, Event Bus, provenance and Odysseus runtime adapters"; Branch="feat/cognitive-foundation"; Builder="core" },
        @{ Name="CLEMENT_STUDIO_INTENT"; Description="CLEMENT Intent Core and deterministic Intent Compiler"; Branch="feat/intent-core-mvp"; Builder="intent" },
        @{ Name="CLEMENT_STUDIO_KNOWLEDGE"; Description="CLEMENT Knowledge Core, ontology, entity resolution and Digital Twin primitives"; Branch="feat/knowledge-core-mvp"; Builder="knowledge" }
    )

    $Results = @()

    foreach ($Spec in $Specs) {
        $RepoPath = Initialize-Repository -Name $Spec.Name -Description $Spec.Description -FeatureBranch $Spec.Branch

        Write-Host ""
        Write-Host "=== GENERATE_CODE=$($Spec.Name) ==="
        switch ($Spec.Builder) {
            "core" { Build-CoreRepo $RepoPath }
            "intent" { Build-IntentRepo $RepoPath }
            "knowledge" { Build-KnowledgeRepo $RepoPath }
            default { throw "UNKNOWN_BUILDER=$($Spec.Builder)" }
        }

        Write-Host "=== TEST=$($Spec.Name) ==="
        $OldPythonPath = $env:PYTHONPATH
        try {
            $env:PYTHONPATH = Join-Path $RepoPath "src"
            & $OdysseusPython -m compileall -q (Join-Path $RepoPath "src")
            if ($LASTEXITCODE -ne 0) { throw "COMPILE_FAIL=$($Spec.Name)" }
            & $OdysseusPython -m pytest -q (Join-Path $RepoPath "tests")
            if ($LASTEXITCODE -ne 0) { throw "UNIT_TESTS_FAIL=$($Spec.Name)" }
        }
        finally {
            $env:PYTHONPATH = $OldPythonPath
        }
        Write-Host "UNIT_TESTS=PASS REPO=$($Spec.Name)"

        Invoke-Git $RepoPath add .
        $Changes = @(& git -C $RepoPath status --porcelain)
        if ($Changes.Count -gt 0) {
            & git -C $RepoPath commit -m "feat: bootstrap cognitive core MVP"
            if ($LASTEXITCODE -ne 0) { throw "COMMIT_FAIL=$($Spec.Name)" }
        }
        else {
            Write-Host "COMMIT_SKIPPED=NO_CHANGES REPO=$($Spec.Name)"
        }

        Invoke-Git $RepoPath push -u origin $Spec.Branch
        $Head = (& git -C $RepoPath rev-parse HEAD).Trim()

        $FullName = "$Owner/$($Spec.Name)"
        $ExistingPr = (& gh pr list --repo $FullName --head $Spec.Branch --base develop --state open --json number --jq '.[0].number' 2>$null)
        if ([string]::IsNullOrWhiteSpace($ExistingPr)) {
            $Body = @"
## CLEMENT Cognitive OS production

Initial production scaffold for `$($Spec.Name)`.

- GitHub-first feature branch
- deterministic MVP contracts
- Python 3.11/3.13 CI
- unit tests
- no merge/tag/release requested

Architecture source: `CLEMENT_STUDIO_P0_BOOTSTRAP` / `feat/cognitive-core-production`.
"@
            gh pr create --repo $FullName --base develop --head $Spec.Branch --title "feat: bootstrap cognitive core MVP" --body $Body --draft
            if ($LASTEXITCODE -ne 0) { throw "PR_CREATE_FAIL=$($Spec.Name)" }
        }
        else {
            Write-Host "DRAFT_PR_ALREADY_EXISTS=$ExistingPr REPO=$($Spec.Name)"
        }

        $Results += [PSCustomObject]@{
            Repository = $Spec.Name
            Branch = $Spec.Branch
            Head = $Head
            Tests = "PASS"
        }
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "COGNITIVE_CORE_PRODUCTION=PASS"
    foreach ($Result in $Results) {
        Write-Host "REPO=$($Result.Repository) BRANCH=$($Result.Branch) HEAD=$($Result.Head) TESTS=$($Result.Tests)"
    }
    Write-Host "REPOSITORIES_CREATED_OR_REUSED=3"
    Write-Host "DRAFT_PRS=CREATED_OR_REUSED"
    Write-Host "MERGE_EXECUTED=NO"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
    Write-Host "NEXT=EXTEND_MEMORY_KNOWLEDGE_PIPELINE_ORCHESTRATOR"
    Write-Host "============================================================"
}
