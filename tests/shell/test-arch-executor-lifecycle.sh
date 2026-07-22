#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
LIFECYCLE=$ROOT_DIR/scripts/morimil-arch-executor.sh
PREPARE=$ROOT_DIR/scripts/prepare-arch-executor-rootfs.sh
POLICY=$ROOT_DIR/config/nspawn/morimil-arch.nspawn
LIMITS=$ROOT_DIR/config/arch-executor-resource-limits.env
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for path in "$LIFECYCLE" "$PREPARE" "$POLICY" "$LIMITS"; do
    [ -f "$path" ] || fail "required lifecycle file is missing: $path"
done

sh "$LIFECYCLE" help > "$TMP_DIR/help.txt"
for command_name in create start status stop destroy rebuild; do
    grep -Eq "^  ${command_name}[[:space:]]" "$TMP_DIR/help.txt" || fail "help is missing lifecycle command: $command_name"
done

if sh "$LIFECYCLE" unsupported > "$TMP_DIR/unsupported.out" 2> "$TMP_DIR/unsupported.err"; then
    fail 'unknown lifecycle command unexpectedly succeeded'
fi
grep -Fq 'unknown lifecycle command' "$TMP_DIR/unsupported.err" || fail 'unknown command error is unclear'

for forbidden in '--network-veth' '--bind=' '--bind-ro=' '--capability=' '--port='; do
    if grep -Fq -- "$forbidden" "$LIFECYCLE" "$PREPARE"; then
        fail "lifecycle implementation contains forbidden option: $forbidden"
    fi
done

if grep -Eq '(^|[^A-Za-z])pacman([^A-Za-z]|$)' "$LIFECYCLE" "$PREPARE"; then
    fail 'lifecycle implementation must not execute pacman'
fi

grep -Fq -- '--settings=trusted' "$LIFECYCLE" || fail 'start does not require trusted nspawn settings'
grep -Fq -- '--keep-unit' "$LIFECYCLE" || fail 'container can escape the resource-limited service unit'
grep -Fq -- '--property=Delegate=yes' "$LIFECYCLE" || fail 'executor service does not delegate nested cgroups'
grep -Fq -- '--property=CPUAccounting=yes' "$LIFECYCLE" || fail 'CPU accounting is not enabled'
grep -Fq -- "--property=\"CPUQuota=\$CPU_QUOTA_PERCENT%\"" "$LIFECYCLE" || fail 'CPU quota is not applied from the declared limits'
grep -Fq -- '--property=MemoryAccounting=yes' "$LIFECYCLE" || fail 'memory accounting is not enabled'
grep -Fq -- "--property=\"MemoryHigh=\$MEMORY_HIGH_BYTES\"" "$LIFECYCLE" || fail 'MemoryHigh is not applied'
grep -Fq -- "--property=\"MemoryMax=\$MEMORY_MAX_BYTES\"" "$LIFECYCLE" || fail 'MemoryMax is not applied'
grep -Fq -- "--property=\"MemorySwapMax=\$MEMORY_SWAP_MAX_BYTES\"" "$LIFECYCLE" || fail 'MemorySwapMax is not applied'
grep -Fq -- '--property=TasksAccounting=yes' "$LIFECYCLE" || fail 'task accounting is not enabled'
grep -Fq -- "--property=\"TasksMax=\$TASKS_MAX\"" "$LIFECYCLE" || fail 'TasksMax is not applied'

grep -Fq -- '--private-network' "$PREPARE" || fail 'ownership preparation lacks private networking'
grep -Fq -- '--private-users=pick' "$PREPARE" || fail 'ownership preparation lacks private users'
grep -Fq -- '--private-users-ownership=chown' "$PREPARE" || fail 'ownership preparation does not shift rootfs ownership'
grep -Fq 'NoNewPrivileges=yes' "$POLICY" || fail 'policy lacks NoNewPrivileges'
grep -Fq 'ReadOnly=yes' "$POLICY" || fail 'policy lacks read-only root'
grep -Fq 'TemporaryFileSystem=/var:mode=0755,nodev,nosuid,size=268435456,nr_inodes=65536' "$POLICY" || fail 'policy lacks capped volatile /var'
if grep -Fq 'Volatile=state' "$POLICY"; then
    fail 'uncapped Volatile=state must not replace the explicit /var tmpfs limit'
fi
grep -Fq 'Private=yes' "$POLICY" || fail 'policy lacks private network'
grep -Fq 'VirtualEthernet=no' "$POLICY" || fail 'policy permits a virtual Ethernet interface'

grep -Fq "fail 'executor must be stopped before destroy'" "$LIFECYCLE" || fail 'destroy does not refuse a running executor'
grep -Fq "fail 'executor service must be stopped before destroy'" "$LIFECYCLE" || fail 'destroy does not refuse an active service'
grep -Fq "fail 'installed policy differs from the repository policy; refusing to remove it'" "$LIFECYCLE" || fail 'destroy does not protect a modified installed policy'
grep -Fq "fail 'installed resource limits differ from the repository limits; refusing to remove them'" "$LIFECYCLE" || fail 'destroy does not protect modified installed limits'

for field in \
    resource_limits_sha256 \
    cpu_quota_percent \
    memory_high_bytes \
    memory_max_bytes \
    memory_swap_max_bytes \
    tasks_max \
    var_size_bytes \
    var_inodes
do
    grep -Fq "${field}=%s" "$LIFECYCLE" || fail "status does not expose resource field: $field"
done

rebuild_block=$(sed -n '/^[[:space:]]*rebuild)$/,/^[[:space:]]*;;/p' "$LIFECYCLE")
printf '%s\n' "$rebuild_block" | grep -Fq 'command_stop' || fail 'rebuild does not stop first'
printf '%s\n' "$rebuild_block" | grep -Fq 'command_destroy' || fail 'rebuild does not destroy the old rootfs'
printf '%s\n' "$rebuild_block" | grep -Fq 'command_create' || fail 'rebuild does not recreate the rootfs'

printf 'Arch executor lifecycle contract tests passed.\n'
