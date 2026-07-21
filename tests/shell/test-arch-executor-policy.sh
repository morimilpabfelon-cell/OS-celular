#!/bin/sh

set -eu

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$TEST_DIR/../..

python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
check = root / "scripts" / "check-arch-executor-policy.sh"
valid = root / "config" / "nspawn" / "morimil-arch.nspawn"


def accepted(path):
    result = subprocess.run(
        ["sh", str(check), str(path)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


if not accepted(valid):
    raise SystemExit("canonical Arch executor policy was rejected")

source = valid.read_text(encoding="utf-8")
cases = {
    "shared host networking": source.replace("Private=yes", "Private=no"),
    "identity UID mapping": source.replace("PrivateUsers=pick", "PrivateUsers=identity"),
    "capability grant": source + "\nCapability=all\n",
    "host device bind": source + "\nBind=/dev:/dev\n",
    "writable root override": source + "\nReadOnly=no\n",
}

with tempfile.TemporaryDirectory(prefix="morimil-arch-policy-") as temp:
    temp_dir = Path(temp)
    for index, (name, content) in enumerate(cases.items()):
        candidate = temp_dir / f"case-{index}.nspawn"
        candidate.write_text(content, encoding="utf-8")
        if accepted(candidate):
            raise SystemExit(f"unsafe policy was accepted: {name}")

    if accepted(temp_dir / "missing.nspawn"):
        raise SystemExit("missing policy was accepted")

print("Arch executor policy contract tests passed.")
PY
