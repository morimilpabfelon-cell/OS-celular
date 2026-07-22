#!/bin/sh

set -eu

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
CHECK=$ROOT_DIR/scripts/check-arch-executor-resource-limits-evidence.sh
LIMITS=$ROOT_DIR/config/arch-executor-resource-limits.env
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ -f "$CHECK" ] || fail "resource evidence checker is missing: $CHECK"
[ -f "$LIMITS" ] || fail "resource limits are missing: $LIMITS"

make_valid_fixture() {
    destination=$1
    mkdir -p "$destination"
    cp "$LIMITS" "$destination/declared-limits.env"

    cat > "$destination/running-status.env" <<'EOF_STATUS'
machine=morimil-arch
created=yes
running=yes
state=running
leader=1234
rootfs_sha256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
uid_shift=479133696
resource_limits_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cpu_quota_percent=100
memory_high_bytes=536870912
memory_max_bytes=805306368
memory_swap_max_bytes=0
tasks_max=256
var_size_bytes=268435456
var_inodes=65536
EOF_STATUS

    cat > "$destination/cgroup-paths.env" <<'EOF_CGROUP'
unit=/system.slice/morimil-arch-resource-limits-ci.service
leader=/system.slice/morimil-arch-resource-limits-ci.service/payload
EOF_CGROUP
    printf '100000 100000\n' > "$destination/cpu.max"
    printf '536870912\n' > "$destination/memory.high"
    printf '805306368\n' > "$destination/memory.max"
    printf '0\n' > "$destination/memory.swap.max"
    printf '256\n' > "$destination/pids.max"
    printf 'tmpfs\n' > "$destination/var-fstype.txt"
    printf 'rw,nosuid,nodev,relatime,size=262144k,nr_inodes=65536\n' > "$destination/var-options.txt"
    printf '268435456\n' > "$destination/var-size-bytes.txt"
    printf '65536\n' > "$destination/var-inodes.txt"
    printf 'rejected=yes\n' > "$destination/var-overflow-test.env"

    cat > "$destination/host-before.env" <<'EOF_HOST'
boot_id=11111111-2222-3333-4444-555555555555
sentinel_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
network_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
net_namespace=net:[4026531840]
pid1_comm=systemd
architecture=aarch64
EOF_HOST
    cp "$destination/host-before.env" "$destination/host-after.env"

    cat > "$destination/cleanup-status.env" <<'EOF_CLEANUP'
rootfs_removed=yes
state_removed=yes
policy_removed=yes
limits_removed=yes
machine_removed=yes
EOF_CLEANUP

    cat > "$destination/resource-limits-summary.env" <<'EOF_SUMMARY'
cgroup_version=2
cpu_limit=yes
memory_high_limit=yes
memory_max_limit=yes
swap_disabled=yes
tasks_limit=yes
var_size_limit=yes
var_inode_limit=yes
var_overflow_rejected=yes
leader_contained=yes
host_unchanged=yes
EOF_SUMMARY

    cat > "$destination/unit-properties.env" <<'EOF_PROPERTIES'
CPUAccounting=yes
MemoryAccounting=yes
TasksAccounting=yes
Delegate=yes
EOF_PROPERTIES
}

accepted() {
    sh "$CHECK" "$1" "$LIMITS" >/dev/null 2>&1
}

VALID=$TMP_DIR/valid
make_valid_fixture "$VALID"
accepted "$VALID" || fail 'canonical resource limit evidence fixture was rejected'

case_number=0
check_mutation() {
    name=$1
    file=$2
    old=$3
    new=$4
    case_number=$((case_number + 1))
    candidate=$TMP_DIR/case-$case_number
    cp -R "$VALID" "$candidate"
    python3 - "$candidate/$file" "$old" "$new" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
text = path.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit(f"mutation source missing in {path.name}: {old!r}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
    if accepted "$candidate"; then
        fail "invalid resource evidence was accepted: $name"
    fi
}

check_mutation 'unlimited CPU' cpu.max '100000 100000' 'max 100000'
check_mutation 'leader escaped unit' cgroup-paths.env '/system.slice/morimil-arch-resource-limits-ci.service/payload' '/machine.slice/machine-morimil.scope'
check_mutation 'wrong memory maximum' memory.max '805306368' '1073741824'
check_mutation 'swap enabled' memory.swap.max '0' '1048576'
check_mutation 'wrong task maximum' pids.max '256' '512'
check_mutation 'larger var size' var-size-bytes.txt '268435456' '536870912'
check_mutation 'overflow accepted' var-overflow-test.env 'rejected=yes' 'rejected=no'
check_mutation 'host changed' host-after.env 'architecture=aarch64' 'architecture=x86_64'
check_mutation 'cleanup incomplete' cleanup-status.env 'limits_removed=yes' 'limits_removed=no'
check_mutation 'summary incomplete' resource-limits-summary.env 'leader_contained=yes' 'leader_contained=no'
check_mutation 'status mismatch' running-status.env 'tasks_max=256' 'tasks_max=512'

missing=$TMP_DIR/missing
cp -R "$VALID" "$missing"
rm "$missing/cpu.max"
if accepted "$missing"; then
    fail 'resource evidence with a missing file was accepted'
fi

printf 'Arch executor resource limit evidence contract tests passed.\n'
