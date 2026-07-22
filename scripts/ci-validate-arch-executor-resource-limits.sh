#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT_DIR/build/arch-executor-resource-limits}
BUILD_PARENT=${BUILD_DIR%/*}
EVIDENCE_DIR=$BUILD_DIR/evidence
MACHINE_ROOT=$BUILD_DIR/machines
STATE_ROOT=$BUILD_DIR/state
MACHINE=morimil-arch
DESTINATION=$MACHINE_ROOT/$MACHINE
STATE_DIR=$STATE_ROOT/arch
INSTALLED_POLICY=/run/systemd/nspawn/$MACHINE.nspawn
INSTALLED_LIMITS=/run/morimil/$MACHINE-resource-limits.env
LOCK_FILE=$BUILD_DIR/resource-limits.lock
UNIT=morimil-arch-resource-limits-ci.service
LIFECYCLE=$ROOT_DIR/scripts/morimil-arch-executor.sh
LIMITS_FILE=$ROOT_DIR/config/arch-executor-resource-limits.env
HOST_SENTINEL=$BUILD_DIR/host-sentinel.txt
CGROUP_ROOT=/sys/fs/cgroup
CLEANUP_REQUIRED=1

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail 'resource limit validation must run as root'
[ "$(uname -m)" = aarch64 ] || fail 'resource limit validation must run natively on AArch64'
[ "$(cat /proc/1/comm)" = systemd ] || fail 'resource limit validation requires systemd as host PID 1'
[ "$(stat -fc %T "$CGROUP_ROOT")" = cgroup2fs ] || fail 'resource limit validation requires unified cgroup v2'
[ ! -e "$BUILD_DIR" ] || fail "build directory already exists: $BUILD_DIR"
[ -f "$LIFECYCLE" ] || fail "lifecycle script is missing: $LIFECYCLE"
[ -f "$LIMITS_FILE" ] || fail "resource limit configuration is missing: $LIMITS_FILE"

for command_name in awk cat chmod cp df fallocate find findmnt grep id machinectl mkdir nsenter readlink rm sha256sum sort stat systemctl tr uname; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

mkdir -p "$EVIDENCE_DIR" /run/systemd/nspawn /run/morimil
chmod 0755 "$BUILD_PARENT" "$BUILD_DIR" "$EVIDENCE_DIR" /run/systemd/nspawn /run/morimil

export ARCH_EXECUTOR_MACHINE="$MACHINE"
export ARCH_EXECUTOR_MACHINE_ROOT="$MACHINE_ROOT"
export ARCH_EXECUTOR_STATE_ROOT="$STATE_ROOT"
export ARCH_EXECUTOR_ROOTFS="$DESTINATION"
export ARCH_EXECUTOR_STATE_DIR="$STATE_DIR"
export ARCH_EXECUTOR_POLICY_FILE="$ROOT_DIR/config/nspawn/morimil-arch.nspawn"
export ARCH_EXECUTOR_INSTALLED_POLICY="$INSTALLED_POLICY"
export ARCH_EXECUTOR_LIMITS_FILE="$LIMITS_FILE"
export ARCH_EXECUTOR_INSTALLED_LIMITS="$INSTALLED_LIMITS"
export ARCH_ROOTFS_PIN_FILE="$ROOT_DIR/config/arch-rootfs-release.env"
export ARCH_ROOTFS_KEY_FILE="$ROOT_DIR/config/keys/archlinuxarm-build-system.asc"
export ARCH_EXECUTOR_BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh"
export ARCH_EXECUTOR_PREPARE_SCRIPT="$ROOT_DIR/scripts/prepare-arch-executor-rootfs.sh"
export ARCH_EXECUTOR_CHECK_LIMITS_SCRIPT="$ROOT_DIR/scripts/check-arch-executor-resource-limits.sh"
export ARCH_EXECUTOR_UNIT="$UNIT"
export ARCH_EXECUTOR_LOCK_FILE="$LOCK_FILE"
export ARCH_EXECUTOR_BOOT_TIMEOUT=180

limit_value() {
    key=$1
    awk -F= -v key="$key" '$1 == key { print $2; exit }' "$LIMITS_FILE"
}

CPU_QUOTA_PERCENT=$(limit_value MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT)
MEMORY_HIGH_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES)
MEMORY_MAX_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_MEMORY_MAX_BYTES)
MEMORY_SWAP_MAX_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES)
TASKS_MAX=$(limit_value MORIMIL_ARCH_EXECUTOR_TASKS_MAX)
VAR_SIZE_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES)
VAR_INODES=$(limit_value MORIMIL_ARCH_EXECUTOR_VAR_INODES)

run_lifecycle() {
    sh "$LIFECYCLE" "$@"
}

machine_exists() {
    machinectl show "$MACHINE" -p Leader --value >/dev/null 2>&1
}

cleanup() {
    if [ "$CLEANUP_REQUIRED" -eq 1 ]; then
        set +e
        run_lifecycle stop >/dev/null 2>&1
        run_lifecycle destroy >/dev/null 2>&1
        rm -rf "$MACHINE_ROOT" "$STATE_ROOT"
        rm -f "$INSTALLED_POLICY" "$INSTALLED_LIMITS"
        set -e
    fi
}
trap cleanup 0 HUP INT TERM

machine_leader() {
    machinectl show "$MACHINE" -p Leader --value
}

run_in_executor() {
    leader=$(machine_leader)
    case "$leader" in
        ''|*[!0-9]*) fail 'executor leader is invalid' ;;
    esac

    nsenter \
        --target "$leader" \
        --user \
        --mount \
        --uts \
        --ipc \
        --net \
        --pid \
        --root="/proc/$leader/root" \
        --wd="/proc/$leader/root" \
        -- "$@"
}

printf 'morimil-host-resource-limit-sentinel-v1\n' > "$HOST_SENTINEL"
HOST_SENTINEL_SHA=$(sha256sum "$HOST_SENTINEL" | awk '{ print $1 }')
HOST_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
HOST_NETNS=$(readlink /proc/1/ns/net)
find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$EVIDENCE_DIR/host-network-before.txt"
HOST_NETWORK_SHA=$(sha256sum "$EVIDENCE_DIR/host-network-before.txt" | awk '{ print $1 }')

cat > "$EVIDENCE_DIR/host-before.env" <<EOF_HOST_BEFORE
boot_id=$HOST_BOOT_ID
sentinel_sha256=$HOST_SENTINEL_SHA
network_sha256=$HOST_NETWORK_SHA
net_namespace=$HOST_NETNS
pid1_comm=$(cat /proc/1/comm)
architecture=$(uname -m)
EOF_HOST_BEFORE

cp "$LIMITS_FILE" "$EVIDENCE_DIR/declared-limits.env"
sh "$ROOT_DIR/scripts/check-arch-executor-resource-limits.sh" "$LIMITS_FILE" > "$EVIDENCE_DIR/limits-validation.txt"
sh "$ROOT_DIR/scripts/check-arch-executor-policy.sh" "$ARCH_EXECUTOR_POLICY_FILE" "$LIMITS_FILE" > "$EVIDENCE_DIR/policy-validation.txt"

run_lifecycle create > "$EVIDENCE_DIR/create-command.env"
run_lifecycle status > "$EVIDENCE_DIR/created-status.env"
run_lifecycle start > "$EVIDENCE_DIR/start-command.env"
run_lifecycle status > "$EVIDENCE_DIR/running-status.env"

leader=$(machine_leader)
case "$leader" in
    ''|*[!0-9]*) fail 'running executor leader is invalid' ;;
esac
[ -r "/proc/$leader/cgroup" ] || fail 'running executor leader lacks cgroup metadata'

unit_cgroup=$(systemctl show "$UNIT" -p ControlGroup --value)
leader_cgroup=$(awk -F: '$1 == "0" { print $3; exit }' "/proc/$leader/cgroup")
case "$unit_cgroup" in
    /*) ;;
    *) fail 'executor unit cgroup path is invalid' ;;
esac
case "$leader_cgroup" in
    /*) ;;
    *) fail 'executor leader cgroup path is invalid' ;;
esac
case "$leader_cgroup" in
    "$unit_cgroup"|"$unit_cgroup"/*) ;;
    *) fail 'executor leader escaped the resource-limited service cgroup' ;;
esac

cat > "$EVIDENCE_DIR/cgroup-paths.env" <<EOF_CGROUP_PATHS
unit=$unit_cgroup
leader=$leader_cgroup
EOF_CGROUP_PATHS

cgroup_dir=$CGROUP_ROOT$unit_cgroup
for filename in cpu.max memory.high memory.max memory.swap.max pids.max; do
    [ -r "$cgroup_dir/$filename" ] || fail "cgroup controller file is missing: $filename"
    cat "$cgroup_dir/$filename" > "$EVIDENCE_DIR/$filename"
done

systemctl show "$UNIT" \
    -p CPUAccounting \
    -p CPUQuotaPerSecUSec \
    -p Delegate \
    -p MemoryAccounting \
    -p MemoryHigh \
    -p MemoryMax \
    -p MemorySwapMax \
    -p TasksAccounting \
    -p TasksMax \
    -p ControlGroup \
    > "$EVIDENCE_DIR/unit-properties.env"

run_in_executor /usr/bin/findmnt -n -o FSTYPE /var > "$EVIDENCE_DIR/var-fstype.txt"
run_in_executor /usr/bin/findmnt -n -o OPTIONS /var > "$EVIDENCE_DIR/var-options.txt"
run_in_executor /usr/bin/df -B1 --output=size /var | awk 'NR == 2 { print $1 }' > "$EVIDENCE_DIR/var-size-bytes.txt"
run_in_executor /usr/bin/df -i --output=itotal /var | awk 'NR == 2 { print $1 }' > "$EVIDENCE_DIR/var-inodes.txt"
run_in_executor /usr/bin/test -x /usr/bin/fallocate || fail 'executor rootfs lacks fallocate for storage enforcement testing'

overflow_size=$((VAR_SIZE_BYTES + 4096))
if run_in_executor /usr/bin/fallocate -l "$overflow_size" /var/morimil-overflow-test.bin >/dev/null 2>&1; then
    overflow_rejected=no
else
    overflow_rejected=yes
fi
run_in_executor /usr/bin/rm -f /var/morimil-overflow-test.bin >/dev/null 2>&1 || true
printf 'rejected=%s\n' "$overflow_rejected" > "$EVIDENCE_DIR/var-overflow-test.env"
[ "$overflow_rejected" = yes ] || fail 'executor /var accepted an allocation larger than its declared limit'

run_lifecycle stop > "$EVIDENCE_DIR/stop-command.env"

AFTER_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
AFTER_SENTINEL_SHA=$(sha256sum "$HOST_SENTINEL" | awk '{ print $1 }')
find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$EVIDENCE_DIR/host-network-after.txt"
AFTER_NETWORK_SHA=$(sha256sum "$EVIDENCE_DIR/host-network-after.txt" | awk '{ print $1 }')

cat > "$EVIDENCE_DIR/host-after.env" <<EOF_HOST_AFTER
boot_id=$AFTER_BOOT_ID
sentinel_sha256=$AFTER_SENTINEL_SHA
network_sha256=$AFTER_NETWORK_SHA
net_namespace=$(readlink /proc/1/ns/net)
pid1_comm=$(cat /proc/1/comm)
architecture=$(uname -m)
EOF_HOST_AFTER

[ "$AFTER_BOOT_ID" = "$HOST_BOOT_ID" ] || fail 'host boot ID changed during resource validation'
[ "$AFTER_SENTINEL_SHA" = "$HOST_SENTINEL_SHA" ] || fail 'host sentinel changed during resource validation'
[ "$AFTER_NETWORK_SHA" = "$HOST_NETWORK_SHA" ] || fail 'host network interfaces changed during resource validation'

run_lifecycle destroy > "$EVIDENCE_DIR/destroy-command.env"
run_lifecycle status > "$EVIDENCE_DIR/destroyed-status.env"

rootfs_removed=no
state_removed=no
policy_removed=no
limits_removed=no
machine_removed=no
[ ! -e "$DESTINATION" ] && rootfs_removed=yes
[ ! -e "$STATE_DIR" ] && state_removed=yes
[ ! -e "$INSTALLED_POLICY" ] && policy_removed=yes
[ ! -e "$INSTALLED_LIMITS" ] && limits_removed=yes
if ! machine_exists; then
    machine_removed=yes
fi

cat > "$EVIDENCE_DIR/cleanup-status.env" <<EOF_CLEANUP
rootfs_removed=$rootfs_removed
state_removed=$state_removed
policy_removed=$policy_removed
limits_removed=$limits_removed
machine_removed=$machine_removed
EOF_CLEANUP

cat > "$EVIDENCE_DIR/resource-limits-summary.env" <<EOF_SUMMARY
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
cpu_quota_percent=$CPU_QUOTA_PERCENT
memory_high_bytes=$MEMORY_HIGH_BYTES
memory_max_bytes=$MEMORY_MAX_BYTES
memory_swap_max_bytes=$MEMORY_SWAP_MAX_BYTES
tasks_max=$TASKS_MAX
var_size_bytes=$VAR_SIZE_BYTES
var_inodes=$VAR_INODES
EOF_SUMMARY

chmod 0644 "$EVIDENCE_DIR"/*
sh "$ROOT_DIR/scripts/check-arch-executor-resource-limits-evidence.sh" "$EVIDENCE_DIR" "$LIMITS_FILE"

CLEANUP_REQUIRED=0
printf 'MORIMIL_ARCH_EXECUTOR_RESOURCE_LIMITS_VALIDATED=yes\n' > "$EVIDENCE_DIR/validation-status.env"
chmod 0644 "$EVIDENCE_DIR/validation-status.env"
printf 'Arch executor resource limit validation passed.\n'
