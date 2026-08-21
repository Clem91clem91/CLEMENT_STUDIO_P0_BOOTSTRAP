from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Stage(str, Enum):
    INPUT_AUDIT = "INPUT_AUDIT"
    TERRAIN = "TERRAIN"
    ASSETS = "ASSETS"
    BLENDER = "BLENDER"
    COMFYUI = "COMFYUI"
    UNREAL = "UNREAL"
    VERIFY = "VERIFY"


DEPENDENCIES = {
    Stage.INPUT_AUDIT: (),
    Stage.TERRAIN: (Stage.INPUT_AUDIT,),
    Stage.ASSETS: (Stage.INPUT_AUDIT,),
    Stage.BLENDER: (Stage.TERRAIN, Stage.ASSETS),
    Stage.COMFYUI: (Stage.INPUT_AUDIT,),
    Stage.UNREAL: (Stage.BLENDER, Stage.COMFYUI),
    Stage.VERIFY: (Stage.UNREAL,),
}


@dataclass(frozen=True, slots=True)
class StageResult:
    stage: Stage
    verdict: str
    evidence_ids: tuple[str, ...] = ()


def execution_plan(target: Stage = Stage.VERIFY) -> tuple[Stage, ...]:
    ordered: list[Stage] = []

    def visit(stage: Stage) -> None:
        for dependency in DEPENDENCIES[stage]:
            visit(dependency)
        if stage not in ordered:
            ordered.append(stage)

    visit(target)
    return tuple(ordered)


def pipeline_verdict(results: list[StageResult], *, target: Stage = Stage.VERIFY) -> str:
    required = set(execution_plan(target))
    by_stage = {result.stage: result for result in results}
    if not required <= set(by_stage):
        return "INCONCLUSIVE"
    for stage in required:
        result = by_stage[stage]
        if result.verdict == "FAIL":
            return "FAIL"
        if result.verdict != "PASS" or not result.evidence_ids:
            return "INCONCLUSIVE"
    return "PASS"
