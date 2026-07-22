#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT_DIR/build/arch-executor-lifecycle}
BUILD_PARENT=${BUILD_DIR%/*}
EVIDENCE_DIR=$BUILD_DIR/evidence
MACHINE_ROOT=$BUILD_DIR/machines
STATE_ROOT=$BUILD_DIR/state
MACHINE=morimil-arch
DESTINATION=$MACHINE_ROOT/$MACHINE
STATE_DIR=$STATE_ROOT/arch
INSTALLED_POLICY=/run/systemd/nspawn/$MACHINE.nspawn
LOCK_FILE=$BUILD_DIR/lifecycle.lock
LIFECYCLE=$ROOT_DIR/scripts/morimil-arch-executor.sh
HOST_SENTINEL=$BUILD_DIR/host-sentinel.txt
CLEANUP_REQUIRED=1

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail 'lifecycle validation must run as root'
[ "$(uname -m)" = aarch64 ] || fail 'lifecycle validation must run natively on AArch64'
[ "$(cat /proc/1/comm)" = systemd ] || fail 'lifecycle validation requires systemd as host PID 1'
[ ! -e "$BUILD_DIR" ] || fail "build directory already exists: $BUILD_DIR"
[ -f "$LIFECYCLE" ] || fail "lifecycle script is missing: $LIFECYCLE"

for command_name in awk cat chmod cp find findmnt grep id machinectl mkdir nsenter readlink rm sha256sum sort systemctl tr uname; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

mkdir -p "$EVIDENCE_DIR" /run/systemd/nspawn
chmod 0755 "$BUILD_PARENT" "$BUILD_DIR" "$EVIDENCE_DIR" /run/systemd/nspawn

export ARCH_EXECUTOR_MACHINE="$MACHINE"
export ARCH_EXECUTOR_MACHINE_ROOT="$MACHINE_ROOT"
export ARCH_EXECUTOR_STATE_ROOT="$STATE_ROOT"
export ARCH_EXECUTOR_ROOTFS="$DESTINATION"
export ARCH_EXECUTOR_STATE_DIR="$STATE_DIR"
export ARCH_EXECUTOR_POLICY_FILE="$ROOT_DIR/config/nspawn/morimil-arch.nspawn"
export ARCH_EXECUTOR_INSTALLED_POLICY="$INSTALLED_POLICY"
export ARCH_ROOTFS_PIN_FILE="$ROOT_DIR/config/arch-rootfs-release.env"
export ARCH_ROOTFS_KEY_FILE="$ROOT_DIR/config/keys/archlinuxarm-build-system.asc"
export ARCH_EXECUTOR_BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh"
export ARCH_EXECUTOR_PREPARE_SCRIPT="$ROOT_DIR/scripts/prepare-arch-executor-rootfs.sh"
export ARCH_EXECUTOR_UNIT=morimil-arch-lifecycle-ci.service
export ARCH_EXECUTOR_LOCK_FILE="$LOCK_FILE"
export ARCH_EXECUTOR_BOOT_TIMEOUT=180

run_lifecycle() {
    sh "$LIFECYCLE" "$@"
}

cleanup() {
    if [ "$CLEANUP_REQUIRED" -eq 1 ]; then
        set +e
        run_lifecycle stop >/dev/null 2>&1
        run_lifecycle destroy >/dev/null 2>&1
        rm -rf "$MACHINE_ROOT" "$STATE_ROOT"
        rm -f "$INSTALLED_POLICY"
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

capture_runtime() {
    label=$1
    leader=$(machine_leader)
    case "$leader" in
        ''|*[!0-9]*) fail "$label executor leader is invalid" ;;
    esac
    [ -r "/proc/$leader/status" ] || fail "$label executor leader disappeared"

    machinectl show "$MACHINE" > "$EVIDENCE_DIR/$label-machine-show.txt"
    machinectl status "$MACHINE" > "$EVIDENCE_DIR/$label-machine-status.txt"
    cat "/proc/$leader/uid_map" > "$EVIDENCE_DIR/$label-uid-map.txt"
    cat "/proc/$leader/gid_map" > "$EVIDENCE_DIR/$label-gid-map.txt"
    awk '$1 == "NoNewPrivs:" { print $2; exit }' "/proc/$leader/status" > "$EVIDENCE_DIR/$label-no-new-privileges.txt"

    container_netns=$(readlink "/proc/$leader/ns/net")
    printf 'host=%s\ncontainer=%s\n' "$HOST_NETNS" "$container_netns" > "$EVIDENCE_DIR/$label-netns.env"

    run_in_executor /usr/bin/cat /run/morimil/executor-ready.env > "$EVIDENCE_DIR/$label-ready.env"
    run_in_executor /usr/bin/findmnt -n -o OPTIONS / > "$EVIDENCE_DIR/$label-root-options.txt"
    run_in_executor /usr/bin/findmnt -n -o FSTYPE /var > "$EVIDENCE_DIR/$label-var-fstype.txt"

    # Expanded by the executor shell, not by this host script.
    # shellcheck disable=SC2016
    run_in_executor /usr/bin/sh -c 'for path in /sys/class/net/*; do [ -e "$path" ] || continue; printf "%s\n" "${path##*/}"; done' \
        | sort > "$EVIDENCE_DIR/$label-network-interfaces.txt"

    if run_in_executor /usr/bin/touch /morimil-root-write-test > "$EVIDENCE_DIR/$label-root-write-test.log" 2>&1; then
        fail "$label executor allowed a write to the root filesystem"
    fi

    run_in_executor /usr/bin/mkdir -p /var/lib/morimil-lifecycle
    run_in_executor /usr/bin/touch /var/lib/morimil-lifecycle/volatile-marker
    run_in_executor /usr/bin/test -f /var/lib/morimil-lifecycle/volatile-marker
}

printf 'morimil-host-lifecycle-sentinel-v1\n' > "$HOST_SENTINEL"
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

run_lifecycle create > "$EVIDENCE_DIR/create-command.env"
run_lifecycle status > "$EVIDENCE_DIR/created-status.env"
cp "$STATE_DIR/rootfs-source.env" "$EVIDENCE_DIR/generation-1-rootfs-source.env"

run_lifecycle start > "$EVIDENCE_DIR/first-start-command.env"
run_lifecycle status > "$EVIDENCE_DIR/first-running-status.env"
capture_runtime first
run_lifecycle stop > "$EVIDENCE_DIR/first-stop-command.env"
run_lifecycle status > "$EVIDENCE_DIR/first-stopped-status.env"
[ ! -e "$DESTINATION/var/lib/morimil-lifecycle/volatile-marker" ] || fail 'volatile marker persisted after first stop'

run_lifecycle rebuild > "$EVIDENCE_DIR/rebuild-command.env"
run_lifecycle status > "$EVIDENCE_DIR/rebuilt-status.env"
cp "$STATE_DIR/rootfs-source.env" "$EVIDENCE_DIR/generation-2-rootfs-source.env"

run_lifecycle start > "$EVIDENCE_DIR/second-start-command.env"
run_lifecycle status > "$EVIDENCE_DIR/second-running-status.env"
capture_runtime second
run_lifecycle stop > "$EVIDENCE_DIR/second-stop-command.env"
[ ! -e "$DESTINATION/var/lib/morimil-lifecycle/volatile-marker" ] || fail 'volatile marker persisted after second stop'

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

[ "$AFTER_BOOT_ID" = "$HOST_BOOT_ID" ] || fail 'host boot ID changed during lifecycle validation'
[ "$AFTER_SENTINEL_SHA" = "$HOST_SENTINEL_SHA" ] || fail 'host sentinel changed during lifecycle validation'
[ "$AFTER_NETWORK_SHA" = "$HOST_NETWORK_SHA" ] || fail 'host network interfaces changed during lifecycle validation'

run_lifecycle destroy > "$EVIDENCE_DIR/destroy-command.env"
run_lifecycle status > "$EVIDENCE_DIR/destroyed-status.env"
[ ! -e "$DESTINATION" ] || fail 'rootfs remained after destroy'
[ ! -e "$STATE_DIR" ] || fail 'state remained after destroy'
[ ! -e "$INSTALLED_POLICY" ] || fail 'installed policy remained after destroy'

cat > "$EVIDENCE_DIR/lifecycle-summary.env" <<'EOF_SUMMARY'
host_architecture=aarch64
create=yes
first_start=yes
first_stop=yes
rebuild=yes
second_start=yes
second_stop=yes
destroy=yes
host_unchanged=yes
rootfs_removed=yes
state_removed=yes
policy_removed=yes
EOF_SUMMARY

chmod 0644 "$EVIDENCE_DIR"/*
sh "$ROOT_DIR/scripts/check-arch-executor-lifecycle-evidence.sh" "$EVIDENCE_DIR"

CLEANUP_REQUIRED=0
printf 'MORIMIL_ARCH_EXECUTOR_LIFECYCLE_VALIDATED=yes\n' > "$EVIDENCE_DIR/validation-status.env"
chmod 0644 "$EVIDENCE_DIR/validation-status.env"
printf 'Arch executor lifecycle validation passed.\n'
