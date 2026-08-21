import pytest

from clement_gpu_manager.gpu import GPUDevice, ReservationManager, parse_nvidia_smi_csv


def test_parse_nvidia_smi_csv() -> None:
    devices = parse_nvidia_smi_csv("0, NVIDIA RTX A4500, 20470, 4096, 42\n")
    assert len(devices) == 1
    gpu = devices[0]
    assert gpu.index == 0
    assert gpu.memory_total_mb == 20470
    assert gpu.memory_used_mb == 4096
    assert gpu.memory_free_mb == 16374


def test_reservations_respect_live_free_vram_and_margin() -> None:
    gpu = GPUDevice(0, "GPU", 20000, 5000, 10)
    manager = ReservationManager()
    reservation = manager.reserve(
        reservation_id="R1",
        owner="blender",
        mode="BLENDER",
        gpu=gpu,
        vram_mb=8000,
        safety_margin_mb=1000,
    )
    assert reservation.vram_mb == 8000
    assert manager.reserved_vram_mb(0) == 8000
    with pytest.raises(RuntimeError, match="VRAM_RESERVATION_DENIED"):
        manager.reserve(
            reservation_id="R2",
            owner="unreal",
            mode="UNREAL",
            gpu=gpu,
            vram_mb=7000,
            safety_margin_mb=1000,
        )


def test_release_frees_reservation_budget() -> None:
    gpu = GPUDevice(0, "GPU", 12000, 2000, 5)
    manager = ReservationManager()
    manager.reserve(reservation_id="R1", owner="agent", mode="AGENT", gpu=gpu, vram_mb=3000)
    released = manager.release("R1")
    assert released.owner == "agent"
    assert manager.reserved_vram_mb(0) == 0
