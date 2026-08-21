import pytest

from clement_comfyui_studio.workflow import WorkflowJob, build_prompt_payload, validate_workflow, verify_outputs


def test_valid_workflow_builds_prompt_payload() -> None:
    workflow = {"1": {"class_type": "ExampleNode", "inputs": {"x": 1}}}
    valid, errors = validate_workflow(workflow)
    assert valid is True
    assert errors == ()
    payload = build_prompt_payload(WorkflowJob("JOB-1", workflow, "client"))
    assert payload["client_id"] == "client"


def test_invalid_workflow_is_rejected() -> None:
    with pytest.raises(ValueError):
        build_prompt_payload(WorkflowJob("JOB-1", {"1": {"inputs": {}}}, "client"))


def test_output_requires_history_and_files_for_verified_evidence() -> None:
    assert verify_outputs(job_id="J", history_id="H", output_files=["out.png"]).verified is True
    assert verify_outputs(job_id="J", history_id=None, output_files=[]).verified is False
