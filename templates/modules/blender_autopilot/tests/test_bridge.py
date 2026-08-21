from clement_blender_autopilot.bridge import BlenderInvocation, verify_artifacts, write_request


def test_headless_command_is_deterministic() -> None:
    invocation = BlenderInvocation("blender.exe", "scene.blend", "runner.py", "request.json")
    assert invocation.command() == (
        "blender.exe",
        "--background",
        "scene.blend",
        "--python",
        "runner.py",
        "--",
        "request.json",
    )


def test_request_and_artifact_verification(tmp_path) -> None:
    request = write_request(tmp_path / "request.json", {"action": "inspect"})
    ok, missing = verify_artifacts([request])
    assert ok is True
    assert missing == ()
    ok, missing = verify_artifacts([tmp_path / "missing.png"])
    assert ok is False
    assert len(missing) == 1
