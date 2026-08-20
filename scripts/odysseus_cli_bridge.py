from __future__ import annotations

import argparse
import json
import runpy
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", required=True)
    parser.add_argument("--argv-file", required=True)
    ns = parser.parse_args()

    cli = Path(ns.cli)
    argv_file = Path(ns.argv_file)

    if not cli.is_file():
        raise SystemExit(f"CLI_NOT_FOUND={cli}")
    if not argv_file.is_file():
        raise SystemExit(f"ARGV_FILE_NOT_FOUND={argv_file}")

    payload = json.loads(argv_file.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, list) or not all(isinstance(item, str) for item in payload):
        raise SystemExit("ARGV_PAYLOAD_MUST_BE_STRING_LIST")

    sys.argv = [str(cli), *payload]
    runpy.run_path(str(cli), run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
