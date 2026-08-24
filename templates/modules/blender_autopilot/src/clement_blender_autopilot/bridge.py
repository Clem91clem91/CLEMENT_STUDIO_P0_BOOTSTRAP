from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class BlenderInvocation:
    blender_executable: str
    blend_file: str
    python_script: str
    request_file: str
    background: bool = True

    def command(self) -> tuple[str, ...]:
        args = [self.blender_executable]
        if self.background:
            args.append("--background")
        args.extend([self.blend_file, "--python", self.python_script, "--", self.request_file])
        return tuple(args)


def write_request(path: str | Path, payload: dict) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return target


def verify_artifacts(paths: list[str | Path]) -> tuple[bool, tuple[str, ...]]:
    missing = tuple(str(path) for path in paths if not Path(path).exists())
    return not missing, missing
