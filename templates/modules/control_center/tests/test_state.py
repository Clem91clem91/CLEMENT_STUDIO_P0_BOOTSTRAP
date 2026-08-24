import json

from clement_control_center.state import dashboard_payload, load_task_snapshot


def test_dashboard_keeps_metrics_distinct(tmp_path) -> None:
    report = {
        "task_id": "TASK-1",
        "agents": [{"id": "A1"}, {"id": "A2"}],
        "coalitions": [{"id": "C1"}],
        "tool_calls": [{}, {}, {}],
        "errors": [],
        "result": "PASS",
    }
    report_path = tmp_path / "TASK_REPORT.json"
    report_path.write_text(json.dumps(report), encoding="utf-8")
    evidence_path = tmp_path / "RAW_EVIDENCE.jsonl"
    evidence_path.write_text("{}\n{}\n{}\n", encoding="utf-8")
    snapshot = load_task_snapshot(report_path, evidence_path)
    payload = dashboard_payload(snapshot)
    assert payload["metrics"]["agent_count"] == 2
    assert payload["metrics"]["coalition_count"] == 1
    assert payload["metrics"]["tool_call_count"] == 3
    assert payload["metrics"]["evidence_count"] == 3
