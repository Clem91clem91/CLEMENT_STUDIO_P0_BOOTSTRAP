from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "scripts" / "odysseus_cli_bridge.py"


def test_bridge_preserves_structured_json_arguments(tmp_path: Path):
    dummy_cli = tmp_path / "dummy_cli.py"
    dummy_cli.write_text(
        "import json, sys\n"
        "print(json.dumps(sys.argv[1:]))\n",
        encoding="utf-8",
    )

    args_json = '["-m","clement_skills_mcp.server"]'
    env_json = '{"CLEMENT_SKILLS_HUB_ROOT":"C:\\\\Users\\\\Shadow\\\\Documents\\\\CLEMENT_STUDIO"}'
    argv = [
        "add",
        "--name",
        "CLEMENT Skills MCP",
        "--transport",
        "stdio",
        "--command",
        r"C:\\Tools\\python.exe",
        "--args",
        args_json,
        "--env",
        env_json,
    ]
    payload = tmp_path / "argv.json"
    payload.write_text(json.dumps(argv), encoding="utf-8")

    completed = subprocess.run(
        [
            sys.executable,
            str(BRIDGE),
            "--cli",
            str(dummy_cli),
            "--argv-file",
            str(payload),
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    received = json.loads(completed.stdout)
    assert received == argv
    assert received[received.index("--args") + 1] == args_json
    assert received[received.index("--env") + 1] == env_json
