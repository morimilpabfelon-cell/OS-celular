#!/bin/sh

set -eu

EVIDENCE_DIR=${1:-build/arch-executor-resource-limits/evidence}
LIMITS_CONFIG=${2:-config/arch-executor-resource-limits.env}

[ -d "$EVIDENCE_DIR" ] || {
    printf 'error: resource limit evidence directory is missing: %s\n' "$EVIDENCE_DIR" >&2
    exit 1
}
[ -f "$LIMITS_CONFIG" ] || {
    printf 'error: resource limit configuration is missing: %s\n' "$LIMITS_CONFIG" >&2
    exit 1
}

python3 - "$EVIDENCE_DIR" "$LIMITS_CONFIG" <<'PY'
from pathlib import Path
import sys

evidence = Path(sys.argv[1])
limits_path = Path(sys.argv[2])

required_files = {
    "cleanup-status.env",
    "cgroup-paths.env",
    "cpu.max",
    "declared-limits.env",
    "host-after.env",
    "host-before.env",
    "memory.high",
    "memory.max",
    "memory.swap.max",
    "pids.max",
    "resource-limits-summary.env",
    "running-status.env",
    "unit-properties.env",
    "var-fstype.txt",
    "var-inodes.txt",
    "var-options.txt",
    "var-overflow-test.env",
    "var-size-bytes.txt",
}
missing = sorted(name for name in required_files if not (evidence / name).is_file())
if missing:
    raise SystemExit(f"error: resource limit evidence is missing files: {missing}")


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw_line:
            continue
        if "=" not in raw_line:
            raise SystemExit(f"error: invalid evidence line {path.name}:{number}")
        key, value = raw_line.split("=", 1)
        if not key or key in values:
            raise SystemExit(f"error: duplicate or empty evidence key {path.name}:{number}")
        values[key] = value
    return values


def scalar(name: str) -> str:
    lines = (evidence / name).read_text(encoding="utf-8").splitlines()
    if len(lines) != 1 or not lines[0]:
        raise SystemExit(f"error: {name} must contain exactly one value")
    return lines[0]


declared = read_env(limits_path)
archived = read_env(evidence / "declared-limits.env")
if archived != declared:
    raise SystemExit("error: archived resource limits differ from the validated configuration")

status = read_env(evidence / "running-status.env")
expected_status = {
    "created": "yes",
    "running": "yes",
    "state": "running",
    "cpu_quota_percent": declared["MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT"],
    "memory_high_bytes": declared["MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES"],
    "memory_max_bytes": declared["MORIMIL_ARCH_EXECUTOR_MEMORY_MAX_BYTES"],
    "memory_swap_max_bytes": declared["MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES"],
    "tasks_max": declared["MORIMIL_ARCH_EXECUTOR_TASKS_MAX"],
    "var_size_bytes": declared["MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES"],
    "var_inodes": declared["MORIMIL_ARCH_EXECUTOR_VAR_INODES"],
}
for key, expected in expected_status.items():
    if status.get(key) != expected:
        raise SystemExit(f"error: running status {key} must equal {expected!r}")
if len(status.get("resource_limits_sha256", "")) != 64:
    raise SystemExit("error: running status lacks a SHA-256 for resource limits")

paths = read_env(evidence / "cgroup-paths.env")
unit_path = paths.get("unit")
leader_path = paths.get("leader")
if not unit_path or not unit_path.startswith("/"):
    raise SystemExit("error: unit cgroup path is invalid")
if not leader_path or not leader_path.startswith("/"):
    raise SystemExit("error: leader cgroup path is invalid")
if leader_path != unit_path and not leader_path.startswith(unit_path.rstrip("/") + "/"):
    raise SystemExit("error: executor leader escaped the resource-limited unit cgroup")

cpu_tokens = scalar("cpu.max").split()
if len(cpu_tokens) != 2 or cpu_tokens[0] == "max":
    raise SystemExit("error: cpu.max does not contain a finite quota and period")
try:
    cpu_quota, cpu_period = map(int, cpu_tokens)
except ValueError as exc:
    raise SystemExit("error: cpu.max contains non-numeric values") from exc
cpu_percent = int(declared["MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT"])
if cpu_quota * 100 != cpu_period * cpu_percent:
    raise SystemExit("error: cpu.max does not enforce the declared CPU percentage")

exact_cgroup_values = {
    "memory.high": declared["MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES"],
    "memory.max": declared["MORIMIL_ARCH_EXECUTOR_MEMORY_MAX_BYTES"],
    "memory.swap.max": declared["MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES"],
    "pids.max": declared["MORIMIL_ARCH_EXECUTOR_TASKS_MAX"],
}
for filename, expected in exact_cgroup_values.items():
    if scalar(filename) != expected:
        raise SystemExit(f"error: {filename} does not equal the declared limit")

if scalar("var-fstype.txt") != "tmpfs":
    raise SystemExit("error: /var is not backed by tmpfs")
if scalar("var-size-bytes.txt") != declared["MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES"]:
    raise SystemExit("error: /var size does not equal the declared storage limit")
if scalar("var-inodes.txt") != declared["MORIMIL_ARCH_EXECUTOR_VAR_INODES"]:
    raise SystemExit("error: /var inode count does not equal the declared limit")
options = set(scalar("var-options.txt").split(","))
for required in {"rw", "nodev", "nosuid"}:
    if required not in options:
        raise SystemExit(f"error: /var tmpfs is missing mount option {required}")

overflow = read_env(evidence / "var-overflow-test.env")
if overflow != {"rejected": "yes"}:
    raise SystemExit("error: /var overflow allocation was not rejected")

before = read_env(evidence / "host-before.env")
after = read_env(evidence / "host-after.env")
for key in ("boot_id", "sentinel_sha256", "network_sha256", "net_namespace", "pid1_comm", "architecture"):
    if before.get(key) != after.get(key):
        raise SystemExit(f"error: host evidence changed across resource validation: {key}")
if before.get("pid1_comm") != "systemd" or before.get("architecture") != "aarch64":
    raise SystemExit("error: host evidence does not identify native AArch64 systemd")

cleanup = read_env(evidence / "cleanup-status.env")
for key in ("rootfs_removed", "state_removed", "policy_removed", "limits_removed", "machine_removed"):
    if cleanup.get(key) != "yes":
        raise SystemExit(f"error: cleanup did not confirm {key}")

summary = read_env(evidence / "resource-limits-summary.env")
for key in (
    "cpu_limit",
    "memory_high_limit",
    "memory_max_limit",
    "swap_disabled",
    "tasks_limit",
    "var_size_limit",
    "var_inode_limit",
    "var_overflow_rejected",
    "leader_contained",
    "host_unchanged",
):
    if summary.get(key) != "yes":
        raise SystemExit(f"error: resource limit summary did not confirm {key}")
if summary.get("cgroup_version") != "2":
    raise SystemExit("error: resource validation did not run on cgroup v2")

print("Arch executor resource limit evidence passed.")
PY
