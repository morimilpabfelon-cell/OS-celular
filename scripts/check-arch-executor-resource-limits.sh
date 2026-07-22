#!/bin/sh

set -eu

CONFIG=${1:-config/arch-executor-resource-limits.env}

[ -f "$CONFIG" ] || {
    printf 'error: Arch executor resource limits are missing: %s\n' "$CONFIG" >&2
    exit 1
}

python3 - "$CONFIG" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
required = {
    "MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT",
    "MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES",
    "MORIMIL_ARCH_EXECUTOR_MEMORY_MAX_BYTES",
    "MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES",
    "MORIMIL_ARCH_EXECUTOR_TASKS_MAX",
    "MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES",
    "MORIMIL_ARCH_EXECUTOR_VAR_INODES",
}

values: dict[str, int] = {}
for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    if not raw_line or raw_line.startswith("#"):
        continue
    match = re.fullmatch(r"([A-Z0-9_]+)=([0-9]+)", raw_line)
    if match is None:
        raise SystemExit(f"error: invalid resource limit line {number}: {raw_line!r}")
    key, raw_value = match.groups()
    if key in values:
        raise SystemExit(f"error: duplicate resource limit: {key}")
    values[key] = int(raw_value)

actual = set(values)
if actual != required:
    missing = sorted(required - actual)
    extra = sorted(actual - required)
    raise SystemExit(
        f"error: resource limit key mismatch; missing={missing or 'none'} "
        f"extra={extra or 'none'}"
    )

cpu = values["MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT"]
memory_high = values["MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES"]
memory_max = values["MORIMIL_ARCH_EXECUTOR_MEMORY_MAX_BYTES"]
swap_max = values["MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES"]
tasks_max = values["MORIMIL_ARCH_EXECUTOR_TASKS_MAX"]
var_size = values["MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES"]
var_inodes = values["MORIMIL_ARCH_EXECUTOR_VAR_INODES"]

mib = 1024 * 1024
if not 10 <= cpu <= 400:
    raise SystemExit("error: CPU quota must be between 10 and 400 percent")
if not 128 * mib <= memory_high <= 8 * 1024 * mib:
    raise SystemExit("error: MemoryHigh must be between 128 MiB and 8 GiB")
if not memory_high <= memory_max <= 8 * 1024 * mib:
    raise SystemExit("error: MemoryMax must be at least MemoryHigh and at most 8 GiB")
if swap_max != 0:
    raise SystemExit("error: MemorySwapMax must remain zero")
if not 32 <= tasks_max <= 4096:
    raise SystemExit("error: TasksMax must be between 32 and 4096")
if not 64 * mib <= var_size <= 4 * 1024 * mib:
    raise SystemExit("error: /var tmpfs size must be between 64 MiB and 4 GiB")
if not 4096 <= var_inodes <= 1048576:
    raise SystemExit("error: /var inode limit must be between 4096 and 1048576")
PY

printf 'Arch executor resource limits passed.\n'
printf 'This result validates declared bounds only; it does not prove cgroup or tmpfs enforcement.\n'
