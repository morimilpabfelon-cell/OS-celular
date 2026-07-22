#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
COMMAND=${1:-help}
[ "$#" -eq 0 ] || shift

MACHINE=${ARCH_EXECUTOR_MACHINE:-morimil-arch}
MACHINE_ROOT=${ARCH_EXECUTOR_MACHINE_ROOT:-/var/lib/machines}
STATE_ROOT=${ARCH_EXECUTOR_STATE_ROOT:-/var/lib/morimil/executors}
DESTINATION=${ARCH_EXECUTOR_ROOTFS:-$MACHINE_ROOT/$MACHINE}
STATE_DIR=${ARCH_EXECUTOR_STATE_DIR:-$STATE_ROOT/arch}
POLICY_FILE=${ARCH_EXECUTOR_POLICY_FILE:-$ROOT_DIR/config/nspawn/morimil-arch.nspawn}
INSTALLED_POLICY=${ARCH_EXECUTOR_INSTALLED_POLICY:-/etc/systemd/nspawn/$MACHINE.nspawn}
LIMITS_FILE=${ARCH_EXECUTOR_LIMITS_FILE:-$ROOT_DIR/config/arch-executor-resource-limits.env}
INSTALLED_LIMITS=${ARCH_EXECUTOR_INSTALLED_LIMITS:-/etc/morimil/arch-executor-resource-limits.env}
PIN_FILE=${ARCH_ROOTFS_PIN_FILE:-$ROOT_DIR/config/arch-rootfs-release.env}
KEY_FILE=${ARCH_ROOTFS_KEY_FILE:-$ROOT_DIR/config/keys/archlinuxarm-build-system.asc}
BOOTSTRAP_SCRIPT=${ARCH_EXECUTOR_BOOTSTRAP_SCRIPT:-$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh}
PREPARE_SCRIPT=${ARCH_EXECUTOR_PREPARE_SCRIPT:-$ROOT_DIR/scripts/prepare-arch-executor-rootfs.sh}
CHECK_LIMITS_SCRIPT=${ARCH_EXECUTOR_CHECK_LIMITS_SCRIPT:-$ROOT_DIR/scripts/check-arch-executor-resource-limits.sh}
UNIT=${ARCH_EXECUTOR_UNIT:-morimil-arch-executor.service}
LOCK_FILE=${ARCH_EXECUTOR_LOCK_FILE:-/run/lock/morimil-arch-executor.lock}
BOOT_TIMEOUT=${ARCH_EXECUTOR_BOOT_TIMEOUT:-180}
PREPARED_FILE=$STATE_DIR/runtime-prepared.env
SOURCE_FILE=$STATE_DIR/rootfs-source.env

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF_USAGE'
Usage: sudo sh scripts/morimil-arch-executor.sh COMMAND

Commands:
  create   Download, authenticate and prepare the pinned Arch rootfs.
  start    Start the prepared executor with enforced resource limits.
  status   Print stable machine-readable lifecycle and limit state.
  stop     Request a clean shutdown and preserve the rootfs.
  destroy  Remove a stopped executor, its state and installed policy.
  rebuild  Stop, destroy and recreate the executor; leave it stopped.
  help     Show this help.
EOF_USAGE
}

case "$COMMAND" in
    help|-h|--help)
        [ "$#" -eq 0 ] || fail 'help does not accept arguments'
        usage
        exit 0
        ;;
    create|start|status|stop|destroy|rebuild) ;;
    *) fail "unknown lifecycle command: $COMMAND" ;;
esac
[ "$#" -eq 0 ] || fail "$COMMAND does not accept arguments"

case "$MACHINE" in
    ''|*[!A-Za-z0-9_.-]*) fail 'ARCH_EXECUTOR_MACHINE contains unsupported characters' ;;
esac
case "$UNIT" in
    ''|*[!A-Za-z0-9_.@:-]*) fail 'ARCH_EXECUTOR_UNIT contains unsupported characters' ;;
esac
case "$BOOT_TIMEOUT" in
    ''|*[!0-9]*) fail 'ARCH_EXECUTOR_BOOT_TIMEOUT must be numeric' ;;
esac
[ "$BOOT_TIMEOUT" -ge 30 ] || fail 'ARCH_EXECUTOR_BOOT_TIMEOUT must be at least 30 seconds'

for path_value in \
    "$MACHINE_ROOT" \
    "$STATE_ROOT" \
    "$DESTINATION" \
    "$STATE_DIR" \
    "$INSTALLED_POLICY" \
    "$INSTALLED_LIMITS" \
    "$LOCK_FILE"
do
    case "$path_value" in
        /*) ;;
        *) fail "lifecycle path must be absolute: $path_value" ;;
    esac
done
[ "$DESTINATION" = "$MACHINE_ROOT/$MACHINE" ] || fail 'executor rootfs must be the named machine below ARCH_EXECUTOR_MACHINE_ROOT'
case "$STATE_DIR" in
    "$STATE_ROOT"/*) ;;
    *) fail 'executor state must be below ARCH_EXECUTOR_STATE_ROOT' ;;
esac
case "$INSTALLED_POLICY" in
    */"$MACHINE.nspawn") ;;
    *) fail 'installed policy filename must match the executor machine name' ;;
esac
case "$DESTINATION:$STATE_DIR:$INSTALLED_POLICY:$INSTALLED_LIMITS:$LOCK_FILE" in
    *'/../'*|*'/..:'*|*'/./'*|*'/.:'*) fail 'lifecycle paths must not contain dot path components' ;;
esac

[ "$(id -u)" -eq 0 ] || fail 'root privileges are required for executor lifecycle operations'
for command_name in awk chmod cmp cp flock id machinectl mkdir mv nsenter rm sha256sum sleep systemctl systemd-run; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done
[ -f "$LIMITS_FILE" ] || fail "resource limit configuration is missing: $LIMITS_FILE"
[ -f "$CHECK_LIMITS_SCRIPT" ] || fail "resource limit validator is missing: $CHECK_LIMITS_SCRIPT"
sh "$CHECK_LIMITS_SCRIPT" "$LIMITS_FILE" >/dev/null
sh "$ROOT_DIR/scripts/check-arch-executor-policy.sh" "$POLICY_FILE" "$LIMITS_FILE" >/dev/null

limit_value() {
    key=$1
    value=$(awk -F= -v key="$key" '$1 == key { print $2; exit }' "$LIMITS_FILE")
    [ -n "$value" ] || fail "resource limit is missing after validation: $key"
    printf '%s\n' "$value"
}

CPU_QUOTA_PERCENT=$(limit_value MORIMIL_ARCH_EXECUTOR_CPU_QUOTA_PERCENT)
MEMORY_HIGH_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_MEMORY_HIGH_BYTES)
MEMORY_MAX_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_MEMORY_MAX_BYTES)
MEMORY_SWAP_MAX_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_MEMORY_SWAP_MAX_BYTES)
TASKS_MAX=$(limit_value MORIMIL_ARCH_EXECUTOR_TASKS_MAX)
VAR_SIZE_BYTES=$(limit_value MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES)
VAR_INODES=$(limit_value MORIMIL_ARCH_EXECUTOR_VAR_INODES)
LIMITS_SHA256=$(sha256sum "$LIMITS_FILE" | awk '{ print $1 }')

mkdir -p "${LOCK_FILE%/*}"
exec 9> "$LOCK_FILE"
flock -n 9 || fail 'another Arch executor lifecycle operation is already running'

machine_leader() {
    machinectl show "$MACHINE" -p Leader --value 2>/dev/null
}

machine_is_running() {
    leader=$(machine_leader) || return 1
    case "$leader" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -r "/proc/$leader/status" ]
}

unit_is_active() {
    systemctl is-active --quiet "$UNIT" >/dev/null 2>&1
}

policy_matches() {
    [ -f "$POLICY_FILE" ] && \
        [ -f "$INSTALLED_POLICY" ] && \
        cmp "$POLICY_FILE" "$INSTALLED_POLICY" >/dev/null 2>&1
}

limits_match() {
    [ -f "$LIMITS_FILE" ] && \
        [ -f "$INSTALLED_LIMITS" ] && \
        cmp "$LIMITS_FILE" "$INSTALLED_LIMITS" >/dev/null 2>&1
}

executor_is_created() {
    [ -d "$DESTINATION" ] && \
        [ -f "$SOURCE_FILE" ] && \
        [ -f "$PREPARED_FILE" ] && \
        policy_matches && \
        limits_match
}

run_in_executor() {
    leader=$(machine_leader) || return 1
    case "$leader" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -r "/proc/$leader/status" ] || return 1

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

wait_until_ready() {
    remaining=$BOOT_TIMEOUT
    while [ "$remaining" -gt 0 ]; do
        if machine_is_running; then
            if run_in_executor /usr/bin/test -f /run/morimil/executor-ready.env >/dev/null 2>&1 && \
               run_in_executor /usr/bin/systemctl is-active --quiet morimil-executor.target >/dev/null 2>&1
            then
                return 0
            fi
        elif ! unit_is_active; then
            return 1
        fi
        sleep 1
        remaining=$((remaining - 1))
    done
    return 1
}

wait_until_stopped() {
    remaining=$BOOT_TIMEOUT
    while [ "$remaining" -gt 0 ]; do
        if ! machine_is_running; then
            return 0
        fi
        sleep 1
        remaining=$((remaining - 1))
    done
    return 1
}

install_configuration() {
    mkdir -p "${INSTALLED_POLICY%/*}" "${INSTALLED_LIMITS%/*}"

    cp "$POLICY_FILE" "$INSTALLED_POLICY.tmp"
    cp "$LIMITS_FILE" "$INSTALLED_LIMITS.tmp"
    chmod 0644 "$INSTALLED_POLICY.tmp" "$INSTALLED_LIMITS.tmp"
    mv "$INSTALLED_POLICY.tmp" "$INSTALLED_POLICY"
    mv "$INSTALLED_LIMITS.tmp" "$INSTALLED_LIMITS"

    policy_matches || fail 'installed nspawn policy differs from repository policy'
    limits_match || fail 'installed resource limits differ from repository limits'
}

rollback_create() {
    rm -rf "$DESTINATION" "$STATE_DIR"
    rm -f \
        "$INSTALLED_POLICY" \
        "$INSTALLED_POLICY.tmp" \
        "$INSTALLED_LIMITS" \
        "$INSTALLED_LIMITS.tmp"
}

command_create() {
    [ ! -e "$DESTINATION" ] || fail "executor rootfs already exists: $DESTINATION"
    [ ! -e "$STATE_DIR" ] || fail "executor state already exists: $STATE_DIR"
    [ ! -e "$INSTALLED_POLICY" ] || fail "installed executor policy already exists: $INSTALLED_POLICY"
    [ ! -e "$INSTALLED_LIMITS" ] || fail "installed resource limits already exist: $INSTALLED_LIMITS"
    [ -f "$PIN_FILE" ] || fail "rootfs pin is missing: $PIN_FILE"
    [ -f "$KEY_FILE" ] || fail "rootfs signing key is missing: $KEY_FILE"
    [ -f "$BOOTSTRAP_SCRIPT" ] || fail "bootstrap script is missing: $BOOTSTRAP_SCRIPT"
    [ -f "$PREPARE_SCRIPT" ] || fail "prepare script is missing: $PREPARE_SCRIPT"

    install_configuration

    if ! ARCH_ROOTFS_PIN_FILE=$PIN_FILE \
         ARCH_ROOTFS_KEY_FILE=$KEY_FILE \
         ARCH_ROOTFS_MACHINE_ROOT=$MACHINE_ROOT \
         ARCH_ROOTFS_STATE_ROOT=$STATE_ROOT \
         ARCH_ROOTFS_DESTINATION=$DESTINATION \
         ARCH_ROOTFS_STATE_DIR=$STATE_DIR \
         sh "$BOOTSTRAP_SCRIPT"
    then
        rollback_create
        fail 'authenticated rootfs bootstrap failed; partial state was removed'
    fi

    if ! ARCH_EXECUTOR_MACHINE=$MACHINE \
         ARCH_EXECUTOR_ROOTFS=$DESTINATION \
         ARCH_EXECUTOR_STATE_DIR=$STATE_DIR \
         sh "$PREPARE_SCRIPT"
    then
        rollback_create
        fail 'executor rootfs preparation failed; partial state was removed'
    fi

    if ! executor_is_created; then
        rollback_create
        fail 'executor creation did not produce a complete lifecycle state'
    fi

    printf 'machine=%s\nstate=stopped\nresult=created\nresource_limits_sha256=%s\n' \
        "$MACHINE" "$LIMITS_SHA256"
}

command_start() {
    executor_is_created || fail 'executor is not completely created or its policy or limits differ'
    if machine_is_running; then
        printf 'machine=%s\nstate=running\nresult=already-running\n' "$MACHINE"
        return 0
    fi
    if unit_is_active; then
        fail 'executor service is active without a registered machine'
    fi

    systemctl start systemd-machined.service
    systemctl is-active --quiet systemd-machined.service || fail 'systemd-machined did not become active'

    systemd-run \
        --quiet \
        --unit="$UNIT" \
        --collect \
        --property=Type=simple \
        --property=KillMode=mixed \
        --property=TimeoutStopSec=30s \
        --property=Delegate=yes \
        --property=CPUAccounting=yes \
        --property="CPUQuota=$CPU_QUOTA_PERCENT%" \
        --property=MemoryAccounting=yes \
        --property="MemoryHigh=$MEMORY_HIGH_BYTES" \
        --property="MemoryMax=$MEMORY_MAX_BYTES" \
        --property="MemorySwapMax=$MEMORY_SWAP_MAX_BYTES" \
        --property=TasksAccounting=yes \
        --property="TasksMax=$TASKS_MAX" \
        -- \
        /usr/bin/systemd-nspawn \
        --quiet \
        --keep-unit \
        --machine="$MACHINE" \
        --directory="$DESTINATION" \
        --settings=trusted \
        --register=yes

    if ! wait_until_ready; then
        systemctl stop "$UNIT" >/dev/null 2>&1 || true
        systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
        fail 'executor did not reach morimil-executor.target'
    fi

    printf 'machine=%s\nstate=running\nresult=started\nresource_limits_sha256=%s\n' \
        "$MACHINE" "$LIMITS_SHA256"
}

command_status() {
    created=no
    running=no
    state=absent
    leader=
    rootfs_sha256=
    uid_shift=

    if [ -d "$DESTINATION" ] || \
       [ -e "$STATE_DIR" ] || \
       [ -e "$INSTALLED_POLICY" ] || \
       [ -e "$INSTALLED_LIMITS" ]
    then
        state=inconsistent
    fi
    if executor_is_created; then
        created=yes
        state=stopped
        rootfs_sha256=$(awk -F= '$1 == "MORIMIL_ROOTFS_SHA256" { print $2; exit }' "$SOURCE_FILE")
        uid_shift=$(awk -F= '$1 == "MORIMIL_ARCH_EXECUTOR_UID_SHIFT" { print $2; exit }' "$PREPARED_FILE")
    fi
    if machine_is_running; then
        running=yes
        state=running
        leader=$(machine_leader)
    elif unit_is_active; then
        state=inconsistent
    fi

    printf 'machine=%s\ncreated=%s\nrunning=%s\nstate=%s\nleader=%s\nrootfs_sha256=%s\nuid_shift=%s\nresource_limits_sha256=%s\ncpu_quota_percent=%s\nmemory_high_bytes=%s\nmemory_max_bytes=%s\nmemory_swap_max_bytes=%s\ntasks_max=%s\nvar_size_bytes=%s\nvar_inodes=%s\n' \
        "$MACHINE" \
        "$created" \
        "$running" \
        "$state" \
        "$leader" \
        "$rootfs_sha256" \
        "$uid_shift" \
        "$LIMITS_SHA256" \
        "$CPU_QUOTA_PERCENT" \
        "$MEMORY_HIGH_BYTES" \
        "$MEMORY_MAX_BYTES" \
        "$MEMORY_SWAP_MAX_BYTES" \
        "$TASKS_MAX" \
        "$VAR_SIZE_BYTES" \
        "$VAR_INODES"

    [ "$state" != inconsistent ]
}

command_stop() {
    if machine_is_running; then
        if ! machinectl poweroff "$MACHINE" >/dev/null 2>&1; then
            machinectl terminate "$MACHINE" >/dev/null 2>&1 || true
        fi
        if ! wait_until_stopped; then
            machinectl terminate "$MACHINE" >/dev/null 2>&1 || true
            wait_until_stopped || fail 'executor remained registered after shutdown request'
        fi
    fi

    if unit_is_active; then
        systemctl stop "$UNIT" >/dev/null 2>&1 || true
    fi
    systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true

    printf 'machine=%s\nstate=stopped\nresult=stopped\n' "$MACHINE"
}

command_destroy() {
    if machine_is_running; then
        fail 'executor must be stopped before destroy'
    fi
    if unit_is_active; then
        fail 'executor service must be stopped before destroy'
    fi

    if [ -e "$INSTALLED_POLICY" ] && ! policy_matches; then
        fail 'installed policy differs from the repository policy; refusing to remove it'
    fi
    if [ -e "$INSTALLED_LIMITS" ] && ! limits_match; then
        fail 'installed resource limits differ from the repository limits; refusing to remove them'
    fi

    rm -rf "$DESTINATION" "$STATE_DIR"
    rm -f \
        "$INSTALLED_POLICY" \
        "$INSTALLED_POLICY.tmp" \
        "$INSTALLED_LIMITS" \
        "$INSTALLED_LIMITS.tmp"

    [ ! -e "$DESTINATION" ] || fail 'executor rootfs removal failed'
    [ ! -e "$STATE_DIR" ] || fail 'executor state removal failed'
    [ ! -e "$INSTALLED_POLICY" ] || fail 'executor policy removal failed'
    [ ! -e "$INSTALLED_LIMITS" ] || fail 'executor resource limit removal failed'

    printf 'machine=%s\nstate=absent\nresult=destroyed\n' "$MACHINE"
}

case "$COMMAND" in
    create) command_create ;;
    start) command_start ;;
    status) command_status ;;
    stop) command_stop ;;
    destroy) command_destroy ;;
    rebuild)
        command_stop
        command_destroy
        command_create
        ;;
esac
