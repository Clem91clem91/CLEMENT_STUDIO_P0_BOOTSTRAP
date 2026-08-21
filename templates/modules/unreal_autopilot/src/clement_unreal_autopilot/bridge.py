from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class UnrealInvocation:
    editor_executable: str
    project_file: str
    python_script: str
    unattended: bool = True

    def command(self) -> tuple[str, ...]:
        args = [self.editor_executable, self.project_file]
        if self.unattended:
            args.extend(["-unattended", "-nop4"])
        args.append(f"-ExecutePythonScript={self.python_script}")
        return tuple(args)


def write_request(path: str | Path, payload: dict) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def validate_asset_evidence(records: list[dict]) -> tuple[bool, tuple[str, ...]]:
    errors: list[str] = []
    for index, record in enumerate(records):
        if not record.get("asset_path"):
            errors.append(f"ASSET_PATH_MISSING={index}")
        if record.get("exists") is not True:
            errors.append(f"ASSET_NOT_VERIFIED={index}")
    return not errors, tuple(errors)
