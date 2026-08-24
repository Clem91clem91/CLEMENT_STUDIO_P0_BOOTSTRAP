from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class TaskSnapshot:
    task_id: str
    result: Any
    agent_count: int
    coalition_count: int
    tool_call_count: int
    evidence_count: int
    error_count: int


def load_task_snapshot(task_report_path: str | Path, raw_evidence_path: str | Path | None = None) -> TaskSnapshot:
    report = json.loads(Path(task_report_path).read_text(encoding="utf-8"))
    evidence_count = 0
    if raw_evidence_path is not None:
        evidence_file = Path(raw_evidence_path)
        if evidence_file.exists():
            evidence_count = sum(1 for line in evidence_file.read_text(encoding="utf-8").splitlines() if line.strip())
    agents = report.get("agents") or []
    coalitions = report.get("coalitions") or []
    tools = report.get("tool_calls") or []
    errors = report.get("errors") or []
    return TaskSnapshot(
        task_id=str(report.get("task_id") or ""),
        result=report.get("result"),
        agent_count=len(agents),
        coalition_count=len(coalitions),
        tool_call_count=len(tools),
        evidence_count=evidence_count,
        error_count=len(errors),
    )


def dashboard_payload(snapshot: TaskSnapshot) -> dict[str, Any]:
    return {
        "task_id": snapshot.task_id,
        "result": snapshot.result,
        "metrics": {
            "agent_count": snapshot.agent_count,
            "coalition_count": snapshot.coalition_count,
            "tool_call_count": snapshot.tool_call_count,
            "evidence_count": snapshot.evidence_count,
            "error_count": snapshot.error_count,
        },
    }
