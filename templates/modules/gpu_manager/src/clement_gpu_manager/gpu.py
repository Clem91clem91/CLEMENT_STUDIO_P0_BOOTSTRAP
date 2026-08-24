from __future__ import annotations

import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass(frozen=True, slots=True)
class GPUDevice:
    index: int
    name: str
    memory_total_mb: int
    memory_used_mb: int
    utilization_percent: float

    @property
    def memory_free_mb(self) -> int:
        return max(0, self.memory_total_mb - self.memory_used_mb)


@dataclass(frozen=True, slots=True)
class TelemetrySnapshot:
    timestamp: str
    devices: tuple[GPUDevice, ...]


@dataclass(frozen=True, slots=True)
class Reservation:
    reservation_id: str
    owner: str
    mode: str
    gpu_index: int
    vram_mb: int
    priority: int


def parse_nvidia_smi_csv(text: str) -> tuple[GPUDevice, ...]:
    devices: list[GPUDevice] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = [part.strip() for part in line.split(",")]
        if len(parts) != 5:
            raise ValueError(f"NVIDIA_SMI_ROW_INVALID={line}")
        devices.append(
            GPUDevice(
                index=int(parts[0]),
                name=parts[1],
                memory_total_mb=int(float(parts[2])),
                memory_used_mb=int(float(parts[3])),
                utilization_percent=float(parts[4]),
            )
        )
    return tuple(devices)


def collect_nvidia_smi() -> TelemetrySnapshot:
    args = [
        "nvidia-smi",
        "--query-gpu=index,name,memory.total,memory.used,utilization.gpu",
        "--format=csv,noheader,nounits",
    ]
    completed = subprocess.run(args, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"NVIDIA_SMI_FAILED={completed.stderr.strip()}")
    return TelemetrySnapshot(datetime.now(timezone.utc).isoformat(), parse_nvidia_smi_csv(completed.stdout))


class ReservationManager:
    MODES = {"IDLE", "AGENT", "IMAGE", "VIDEO", "BLENDER", "UNREAL", "HYBRID"}

    def __init__(self) -> None:
        self._reservations: dict[str, Reservation] = {}

    def reserve(
        self,
        *,
        reservation_id: str,
        owner: str,
        mode: str,
        gpu: GPUDevice,
        vram_mb: int,
        priority: int = 50,
        safety_margin_mb: int = 1024,
    ) -> Reservation:
        mode = mode.upper()
        if mode not in self.MODES:
            raise ValueError(f"RESOURCE_MODE_INVALID={mode}")
        if reservation_id in self._reservations:
            raise ValueError(f"RESERVATION_EXISTS={reservation_id}")
        requested = max(0, int(vram_mb))
        already_reserved = sum(
            item.vram_mb for item in self._reservations.values() if item.gpu_index == gpu.index
        )
        capacity = max(0, gpu.memory_free_mb - max(0, int(safety_margin_mb)) - already_reserved)
        if requested > capacity:
            raise RuntimeError(
                f"VRAM_RESERVATION_DENIED requested={requested} capacity={capacity} gpu={gpu.index}"
            )
        reservation = Reservation(reservation_id, owner, mode, gpu.index, requested, int(priority))
        self._reservations[reservation_id] = reservation
        return reservation

    def release(self, reservation_id: str) -> Reservation:
        if reservation_id not in self._reservations:
            raise KeyError(f"RESERVATION_NOT_FOUND={reservation_id}")
        return self._reservations.pop(reservation_id)

    def list(self, *, gpu_index: int | None = None) -> tuple[Reservation, ...]:
        values = tuple(self._reservations.values())
        if gpu_index is None:
            return values
        return tuple(item for item in values if item.gpu_index == gpu_index)

    def reserved_vram_mb(self, gpu_index: int) -> int:
        return sum(item.vram_mb for item in self.list(gpu_index=gpu_index))
