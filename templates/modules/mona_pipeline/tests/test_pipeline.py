from clement_mona_pipeline.pipeline import Stage, StageResult, execution_plan, pipeline_verdict


def test_plan_respects_dependencies() -> None:
    plan = execution_plan()
    assert plan[0] is Stage.INPUT_AUDIT
    assert plan[-1] is Stage.VERIFY
    assert plan.index(Stage.BLENDER) < plan.index(Stage.UNREAL)
    assert plan.index(Stage.COMFYUI) < plan.index(Stage.UNREAL)


def test_pipeline_needs_evidence_for_every_required_stage() -> None:
    results = [StageResult(stage, "PASS", (f"E-{stage.value}",)) for stage in execution_plan()]
    assert pipeline_verdict(results) == "PASS"
    incomplete = results[:-1]
    assert pipeline_verdict(incomplete) == "INCONCLUSIVE"


def test_any_failed_stage_fails_pipeline() -> None:
    results = [StageResult(stage, "PASS", ("E",)) for stage in execution_plan()]
    results[2] = StageResult(results[2].stage, "FAIL", ("E",))
    assert pipeline_verdict(results) == "FAIL"
