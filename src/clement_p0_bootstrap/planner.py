from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


class BootstrapManifestError(ValueError):
    pass


SUPPORTED_SCHEMA_VERSIONS = {"1.0.0", "1.1.0"}


@dataclass(frozen=True)
class Component:
    id: str
    name: str
    repository: str
    branch: str
    local_dir: str
    depends_on: tuple[str, ...]


def load_manifest(path: str | Path) -> tuple[Path, tuple[Component, ...]]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    schema_version = str(data.get("schema_version") or "")
    if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
        raise BootstrapManifestError(f"unsupported schema_version: {schema_version}")
    root = Path(data.get("root") or "")
    raw_components = data.get("components")
    if not isinstance(raw_components, list) or not raw_components:
        raise BootstrapManifestError("components must be a non-empty list")

    components: list[Component] = []
    ids: set[str] = set()
    for raw in raw_components:
        required = {"id", "name", "repository", "branch", "local_dir", "depends_on"}
        missing = required - set(raw)
        if missing:
            raise BootstrapManifestError(f"missing fields for component: {sorted(missing)}")
        cid = str(raw["id"])
        if cid in ids:
            raise BootstrapManifestError(f"duplicate component id: {cid}")
        ids.add(cid)
        deps = raw["depends_on"]
        if not isinstance(deps, list) or not all(isinstance(item, str) for item in deps):
            raise BootstrapManifestError(f"depends_on must be a string list for {cid}")
        components.append(
            Component(
                id=cid,
                name=str(raw["name"]),
                repository=str(raw["repository"]),
                branch=str(raw["branch"]),
                local_dir=str(raw["local_dir"]),
                depends_on=tuple(deps),
            )
        )

    unknown = sorted({dep for c in components for dep in c.depends_on if dep not in ids})
    if unknown:
        raise BootstrapManifestError(f"unknown dependencies: {unknown}")
    return root, tuple(components)


def plan_components(components: tuple[Component, ...]) -> tuple[Component, ...]:
    """Return a stable topological order without executing any mutation."""
    by_id = {component.id: component for component in components}
    indegree = {component.id: len(component.depends_on) for component in components}
    children: dict[str, list[str]] = {component.id: [] for component in components}
    for component in components:
        for dep in component.depends_on:
            children[dep].append(component.id)

    ready = sorted(cid for cid, degree in indegree.items() if degree == 0)
    ordered: list[Component] = []

    while ready:
        cid = ready.pop(0)
        ordered.append(by_id[cid])
        for child in sorted(children[cid]):
            indegree[child] -= 1
            if indegree[child] == 0:
                ready.append(child)
                ready.sort()

    if len(ordered) != len(components):
        cyclic = sorted(cid for cid, degree in indegree.items() if degree > 0)
        raise BootstrapManifestError(f"dependency cycle detected: {cyclic}")

    return tuple(ordered)
