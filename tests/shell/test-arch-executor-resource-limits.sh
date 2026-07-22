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
check = root / "scripts" / "check-arch-executor-resource-limits.sh"
valid = root / "config" / "arch-executor-resource-limits.env"


def accepted(path: Path) -> bool:
    result = subprocess.run(
        ["sh", str(check), str(path)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


if not accepted(valid):
    raise SystemExit("canonical Arch executor resource limits were rejected")

source = valid.read_text(encoding="utf-8")
cases = {
    "CPU quota below floor": source.replace(
        "MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT=100",
        "MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT=9",
    ),
    "CPU quota above ceiling": source.replace(
        "MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT=100",
        "MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT=401",
    ),
    "MemoryHigh above MemoryMax": source.replace(
        "MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES=536870912",
        "MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES=1073741824",
    ),
    "swap enabled": source.replace(
        "MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES=0",
        "MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES=1",
    ),
    "tasks below floor": source.replace(
        "MORIMIL_ARCH_EXECUTOR_TASKS_MAX=256",
        "MORIMIL_ARCH_EXECUTOR_TASKS_MAX=31",
    ),
    "storage below floor": source.replace(
        "MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES=268435456",
        "MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES=1024",
    ),
    "inode limit above ceiling": source.replace(
        "MORIMIL_ARCH_EXECUTOR_VAR_INODES=65536",
        "MORIMIL_ARCH_EXECUTOR_VAR_INODES=1048577",
    ),
    "non-numeric value": source.replace(
        "MORIMIL_ARCH_EXECUTOR_TASKS_MAX=256",
        "MORIMIL_ARCH_EXECUTOR_TASKS_MAX=two-hundred",
    ),
    "unknown key": source + "MORIMIL_ARCH_EXECUTOR_UNKNOWN=1\n",
    "missing key": source.replace(
        "MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES=0\n", ""
    ),
}

with tempfile.TemporaryDirectory(prefix="morimil-arch-limits-") as temp:
    temp_dir = Path(temp)
    for index, (name, content) in enumerate(cases.items()):
        candidate = temp_dir / f"case-{index}.env"
        candidate.write_text(content, encoding="utf-8")
        if accepted(candidate):
            raise SystemExit(f"invalid resource limits were accepted: {name}")

    if accepted(temp_dir / "missing.env"):
        raise SystemExit("missing resource limits were accepted")

print("Arch executor resource limit contract tests passed.")
PY
