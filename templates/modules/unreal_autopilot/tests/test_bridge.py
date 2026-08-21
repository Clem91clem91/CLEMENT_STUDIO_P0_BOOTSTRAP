from clement_unreal_autopilot.bridge import UnrealInvocation, validate_asset_evidence, write_request


def test_unreal_invocation_is_explicit_and_unattended() -> None:
    invocation = UnrealInvocation("UnrealEditor-Cmd.exe", "Project.uproject", "runner.py")
    command = invocation.command()
    assert command[0] == "UnrealEditor-Cmd.exe"
    assert command[1] == "Project.uproject"
    assert "-unattended" in command
    assert "-nop4" in command
    assert "-ExecutePythonScript=runner.py" in command


def test_asset_evidence_must_prove_paths_exist() -> None:
    ok, errors = validate_asset_evidence([{"asset_path": "/Game/Tree", "exists": True}])
    assert ok is True
    assert errors == ()
    ok, errors = validate_asset_evidence([{"asset_path": "/Game/Missing", "exists": False}])
    assert ok is False
    assert errors == ("ASSET_NOT_VERIFIED=0",)


def test_request_file_is_machine_readable(tmp_path) -> None:
    path = write_request(tmp_path / "request.json", {"action": "inspect_project"})
    assert "inspect_project" in path.read_text(encoding="utf-8")
