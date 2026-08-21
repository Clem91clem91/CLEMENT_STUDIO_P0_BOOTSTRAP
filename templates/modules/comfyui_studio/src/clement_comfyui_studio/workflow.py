from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class WorkflowJob:
    job_id: str
    workflow: Mapping[str, Any]
    client_id: str


@dataclass(frozen=True, slots=True)
class OutputEvidence:
    job_id: str
    history_id: str
    output_files: tuple[str, ...]
    verified: bool


def validate_workflow(workflow: Mapping[str, Any]) -> tuple[bool, tuple[str, ...]]:
    if not workflow:
        return False, ("WORKFLOW_EMPTY",)
    errors: list[str] = []
    for node_id, node in workflow.items():
        if not isinstance(node, Mapping):
            errors.append(f"NODE_NOT_OBJECT={node_id}")
            continue
        if not node.get("class_type"):
            errors.append(f"NODE_CLASS_TYPE_MISSING={node_id}")
        if "inputs" not in node:
            errors.append(f"NODE_INPUTS_MISSING={node_id}")
    return not errors, tuple(errors)


def build_prompt_payload(job: WorkflowJob) -> dict[str, Any]:
    valid, errors = validate_workflow(job.workflow)
    if not valid:
        raise ValueError(";".join(errors))
    return {"prompt": dict(job.workflow), "client_id": job.client_id}


def verify_outputs(*, job_id: str, history_id: str | None, output_files: list[str]) -> OutputEvidence:
    verified = bool(history_id and output_files and all(str(path).strip() for path in output_files))
    return OutputEvidence(job_id, str(history_id or ""), tuple(output_files), verified)
