from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "Register-P002Odysseus.ps1"
BRIDGE = ROOT / "scripts" / "odysseus_cli_bridge.py"


def test_registration_script_is_ascii_for_windows_powershell_51():
    SCRIPT.read_bytes().decode("ascii")


def test_registration_uses_trusted_local_odysseus_cli():
    text = SCRIPT.read_text(encoding="ascii")
    assert "scripts\\odysseus-mcp" in text
    assert '"--transport", "stdio"' in text
    assert "clement_skills_mcp.server" in text
    assert "CLEMENT_SKILLS_HUB_ROOT" in text


def test_registration_uses_structured_argv_bridge_for_json_values():
    text = SCRIPT.read_text(encoding="ascii")
    assert "odysseus_cli_bridge.py" in text
    assert "STRUCTURED_ARGV_FILE" in text
    assert "--argv-file" in text
    assert "$StructuredArgv" in text
    assert "$ArgsJson" in text
    assert "$EnvJson" in text
    assert BRIDGE.is_file()


def test_registration_verifies_command_args_and_hub_after_create_or_reuse():
    text = SCRIPT.read_text(encoding="ascii")
    assert "CONFIG_VERIFICATION=PASS" in text
    assert "VERIFY_COMMAND=" in text
    assert "VERIFY_ARGS=" in text
    assert "VERIFY_HUB=" in text
    assert "ENV_CLEMENT_SKILLS_HUB_ROOT" in text


def test_registration_does_not_disable_security_or_restart_processes():
    text = SCRIPT.read_text(encoding="ascii").lower()
    forbidden = (
        "localhost_bypass=true",
        "auth_enabled=false",
        "stop-process",
        "taskkill",
        "kill-process",
        "restart-computer",
    )
    for token in forbidden:
        assert token not in text
    assert "security_settings_changed=no" in text
    assert "restart_executed=no" in text


def test_registration_never_auto_replaces_mismatched_existing_server():
    text = SCRIPT.read_text(encoding="ascii")
    assert "EXISTING_CONFIGURATION_MISMATCH" in text
    assert "AUTOMATIC_DELETE=NO" in text
    assert "AUTOMATIC_REPLACE=NO" in text
