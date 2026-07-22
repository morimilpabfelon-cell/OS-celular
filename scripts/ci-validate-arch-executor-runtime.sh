#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT_DIR/build/arch-executor-runtime}
BUILD_PARENT=${BUILD_DIR%/*}
PIN_FILE=${ARCH_ROOTFS_PIN_FILE:-$ROOT_DIR/config/arch-rootfs-release.env}
KEY_FILE=${ARCH_ROOTFS_KEY_FILE:-$ROOT_DIR/config/keys/archlinuxarm-build-system.asc}
POLICY_FILE=${ARCH_EXECUTOR_POLICY_FILE:-$ROOT_DIR/config/nspawn/morimil-arch.nspawn}
MACHINE=${ARCH_EXECUTOR_MACHINE:-morimil-arch}
MACHINE_ROOT=$BUILD_DIR/machines
STATE_ROOT=$BUILD_DIR/state
DESTINATION=$MACHINE_ROOT/$MACHINE
STATE_DIR=$STATE_ROOT/arch
EVIDENCE_DIR=$BUILD_DIR/evidence
TRUSTED_POLICY=/run/systemd/nspawn/$MACHINE.nspawn
STATUS_FILE=${ARCH_EXECUTOR_CI_STATUS_FILE:-$ROOT_DIR/arch-executor-runtime-status.txt}
BOOT_TIMEOUT=${ARCH_EXECUTOR_BOOT_TIMEOUT:-240}
NSPAWN_PID=
CURRENT_LOG=
FORCED_FAILURE_EXIT=

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

case "$BOOT_TIMEOUT" in
    *[!0-9]*|'') fail 'ARCH_EXECUTOR_BOOT_TIMEOUT must be numeric' ;;
esac
[ "$BOOT_TIMEOUT" -ge 30 ] || fail 'ARCH_EXECUTOR_BOOT_TIMEOUT must be at least 30 seconds'

[ "$(id -u)" -eq 0 ] || fail 'real Arch executor runtime validation must run as root'
[ ! -e "$BUILD_DIR" ] || fail "build directory already exists: $BUILD_DIR"
[ ! -e "$STATUS_FILE" ] || fail "status file already exists: $STATUS_FILE"
[ "$(uname -m)" = aarch64 ] || fail 'runtime validation must execute natively on an AArch64 host'
[ "$(cat /proc/1/comm)" = systemd ] || fail 'runtime validation requires systemd as host PID 1'

for command_name in \
    awk cat chmod cmp cp find findmnt grep id kill ln machinectl mkdir \
    readlink rm sed sha256sum sleep sort systemctl systemd-nspawn systemd-run tail tr uname
do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

[ -f "$PIN_FILE" ] || fail "Arch rootfs pin is missing: $PIN_FILE"
[ -f "$KEY_FILE" ] || fail "Arch signing key is missing: $KEY_FILE"
[ -f "$POLICY_FILE" ] || fail "Arch executor policy is missing: $POLICY_FILE"

machine_exists() {
    machinectl show "$MACHINE" -p Leader --value >/dev/null 2>&1
}

wait_machine_gone() {
    remaining=$BOOT_TIMEOUT
    while [ "$remaining" -gt 0 ]; do
        if ! machine_exists; then
            return 0
        fi
        sleep 1
        remaining=$((remaining - 1))
    done
    return 1
}

terminate_machine() {
    if machine_exists; then
        machinectl terminate "$MACHINE" >/dev/null 2>&1 || true
        wait_machine_gone || true
    fi
}

cleanup() {
    terminate_machine
    if [ -n "$NSPAWN_PID" ] && kill -0 "$NSPAWN_PID" >/dev/null 2>&1; then
        kill -TERM "$NSPAWN_PID" >/dev/null 2>&1 || true
        sleep 1
        kill -KILL "$NSPAWN_PID" >/dev/null 2>&1 || true
    fi
    rm -f "$TRUSTED_POLICY"
    rm -rf "$MACHINE_ROOT" "$STATE_ROOT"
}
trap cleanup 0 HUP INT TERM

mkdir -p "$EVIDENCE_DIR" /run/systemd/nspawn
chmod 0755 "$BUILD_PARENT" "$BUILD_DIR" "$EVIDENCE_DIR" /run/systemd/nspawn

sh "$ROOT_DIR/scripts/check-arch-executor-policy.sh" "$POLICY_FILE" > "$EVIDENCE_DIR/policy-validation.txt"
sh "$ROOT_DIR/scripts/check-arch-rootfs-pin.sh" "$PIN_FILE" > "$EVIDENCE_DIR/pin-validation.txt"
cp "$POLICY_FILE" "$TRUSTED_POLICY"
chmod 0644 "$TRUSTED_POLICY"
cmp "$POLICY_FILE" "$TRUSTED_POLICY" >/dev/null 2>&1 || fail 'trusted nspawn policy copy differs from repository policy'
sha256sum "$POLICY_FILE" > "$EVIDENCE_DIR/policy.sha256"

systemctl start systemd-machined.service
systemctl is-active --quiet systemd-machined.service || fail 'systemd-machined did not become active'

HOST_SENTINEL=$BUILD_DIR/host-sentinel.txt
printf 'morimil-host-sentinel-v1\n' > "$HOST_SENTINEL"
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

{
    printf 'kernel='; uname -srmo
    printf 'systemd='; systemd-nspawn --version | awk 'NR == 1 { print; exit }'
    printf 'machinectl='; machinectl --version | awk 'NR == 1 { print; exit }'
    printf 'findmnt='; findmnt --version | awk 'NR == 1 { print; exit }'
} > "$EVIDENCE_DIR/environment.txt"

bootstrap_generation() {
    generation=$1
    log=$EVIDENCE_DIR/bootstrap-generation-$generation.log

    ARCH_ROOTFS_PIN_FILE=$PIN_FILE \
    ARCH_ROOTFS_KEY_FILE=$KEY_FILE \
    ARCH_ROOTFS_MACHINE_ROOT=$MACHINE_ROOT \
    ARCH_ROOTFS_STATE_ROOT=$STATE_ROOT \
    ARCH_ROOTFS_DESTINATION=$DESTINATION \
    ARCH_ROOTFS_STATE_DIR=$STATE_DIR \
    sh "$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh" > "$log" 2>&1

    [ -d "$DESTINATION" ] || fail "generation $generation bootstrap did not publish the rootfs"
    [ -f "$STATE_DIR/rootfs-source.env" ] || fail "generation $generation bootstrap did not publish source metadata"
    cp "$STATE_DIR/rootfs-source.env" "$EVIDENCE_DIR/generation-$generation-rootfs-source.env"

    mkdir -p \
        "$DESTINATION/usr/local/libexec" \
        "$DESTINATION/etc/systemd/system" \
        "$DESTINATION/etc/systemd/system/multi-user.target.wants"

    cat > "$DESTINATION/usr/local/libexec/morimil-runtime-proof" <<EOF_PROOF_SCRIPT
#!/bin/sh
set -eu
mkdir -p /run/morimil
interfaces=
for path in /sys/class/net/*; do
    [ -e "\$path" ] || continue
    name=\${path##*/}
    if [ -z "\$interfaces" ]; then
        interfaces=\$name
    else
        interfaces=\$interfaces,\$name
    fi
done
{
    printf 'generation=$generation\\n'
    printf 'pid1_comm='; cat /proc/1/comm
    printf 'network_interfaces=%s\\n' "\$interfaces"
} > /run/morimil/runtime-proof.env
EOF_PROOF_SCRIPT
    chmod 0755 "$DESTINATION/usr/local/libexec/morimil-runtime-proof"

    cat > "$DESTINATION/etc/systemd/system/morimil-runtime-proof.service" <<'EOF_PROOF_UNIT'
[Unit]
Description=Morimil Arch executor runtime proof
After=basic.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/morimil-runtime-proof
RemainAfterExit=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF_PROOF_UNIT

    ln -s ../morimil-runtime-proof.service \
        "$DESTINATION/etc/systemd/system/multi-user.target.wants/morimil-runtime-proof.service"

    rm -f "$DESTINATION/etc/machine-id"
    : > "$DESTINATION/etc/machine-id"
}

run_in_machine() {
    systemd-run --machine="$MACHINE" --quiet --wait --pipe "$@"
}

wait_for_boot() {
    remaining=$BOOT_TIMEOUT
    while [ "$remaining" -gt 0 ]; do
        if [ -n "$NSPAWN_PID" ] && ! kill -0 "$NSPAWN_PID" >/dev/null 2>&1; then
            tail -n 80 "$CURRENT_LOG" >&2 || true
            fail 'systemd-nspawn exited before the container reached multi-user.target'
        fi

        if machine_exists && systemctl --machine="$MACHINE" is-active --quiet multi-user.target; then
            if run_in_machine /usr/bin/test -f /run/morimil/runtime-proof.env >/dev/null 2>&1; then
                return 0
            fi
        fi

        sleep 1
        remaining=$((remaining - 1))
    done

    machinectl status "$MACHINE" >&2 || true
    tail -n 80 "$CURRENT_LOG" >&2 || true
    fail 'container boot timed out'
}

start_machine() {
    label=$1
    [ -z "$NSPAWN_PID" ] || fail 'an nspawn process is already tracked'
    ! machine_exists || fail 'machine is already registered before start'

    CURRENT_LOG=$EVIDENCE_DIR/nspawn-$label.log
    systemd-nspawn \
        --quiet \
        --machine="$MACHINE" \
        --directory="$DESTINATION" \
        --settings=trusted \
        --register=yes \
        > "$CURRENT_LOG" 2>&1 &
    NSPAWN_PID=$!
    wait_for_boot
}

capture_runtime() {
    label=$1
    proof_file=$EVIDENCE_DIR/$label-proof.env
    uid_map_file=$EVIDENCE_DIR/$label-uid-map.txt
    gid_map_file=$EVIDENCE_DIR/$label-gid-map.txt
    no_new_privs_file=$EVIDENCE_DIR/$label-no-new-privileges.txt
    root_options_file=$EVIDENCE_DIR/$label-root-options.txt
    var_fstype_file=$EVIDENCE_DIR/$label-var-fstype.txt
    interfaces_file=$EVIDENCE_DIR/$label-network-interfaces.txt
    netns_file=$EVIDENCE_DIR/$label-netns.env

    leader=$(machinectl show "$MACHINE" -p Leader --value)
    case "$leader" in *[!0-9]*|'') fail "$label machine leader is invalid" ;; esac
    [ -r "/proc/$leader/status" ] || fail "$label machine leader disappeared"

    machinectl show "$MACHINE" > "$EVIDENCE_DIR/$label-machine-show.txt"
    machinectl status "$MACHINE" > "$EVIDENCE_DIR/$label-machine-status.txt"
    cat "/proc/$leader/uid_map" > "$uid_map_file"
    cat "/proc/$leader/gid_map" > "$gid_map_file"
    awk '$1 == "NoNewPrivs:" { print $2; exit }' "/proc/$leader/status" > "$no_new_privs_file"
    [ "$(tr -d '\r\n' < "$no_new_privs_file")" = 1 ] || fail "$label payload lacks NoNewPrivileges"

    container_netns=$(readlink "/proc/$leader/ns/net")
    [ "$container_netns" != "$HOST_NETNS" ] || fail "$label container shares the host network namespace"
    printf 'host=%s\ncontainer=%s\n' "$HOST_NETNS" "$container_netns" > "$netns_file"

    run_in_machine /usr/bin/cat /run/morimil/runtime-proof.env > "$proof_file"
    grep -Fqx 'pid1_comm=systemd' "$proof_file" || fail "$label runtime proof does not identify systemd as PID 1"
    grep -Fqx 'network_interfaces=lo' "$proof_file" || fail "$label runtime proof exposes a non-loopback interface"

    # This program is expanded by the guest shell, not by this host script.
    # shellcheck disable=SC2016
    run_in_machine /usr/bin/sh -c 'for path in /sys/class/net/*; do [ -e "$path" ] || continue; printf "%s\n" "${path##*/}"; done' \
        | sort > "$interfaces_file"
    [ "$(tr '\n' ',' < "$interfaces_file" | sed 's/,$//')" = lo ] || fail "$label container exposes a non-loopback interface"

    run_in_machine /usr/bin/findmnt -n -o OPTIONS / > "$root_options_file"
    root_options=$(tr -d '\r\n' < "$root_options_file")
    case ",$root_options," in *,ro,*) ;; *) fail "$label container root is writable" ;; esac

    if run_in_machine /usr/bin/touch /morimil-root-write-test > "$EVIDENCE_DIR/$label-root-write-test.log" 2>&1; then
        fail "$label container allowed a write to the root filesystem"
    fi

    run_in_machine /usr/bin/findmnt -n -o FSTYPE /var > "$var_fstype_file"
    [ "$(tr -d '\r\n' < "$var_fstype_file")" = tmpfs ] || fail "$label /var is not volatile tmpfs"
    run_in_machine /usr/bin/mkdir -p /var/lib/morimil-runtime
    run_in_machine /usr/bin/touch /var/lib/morimil-runtime/volatile-marker
    run_in_machine /usr/bin/test -f /var/lib/morimil-runtime/volatile-marker

    host_uid_start=$(awk 'NR == 1 { print $2 }' "$uid_map_file")
    case "$host_uid_start" in *[!0-9]*|'') fail "$label UID map is invalid" ;; esac
    [ "$host_uid_start" -ne 0 ] || fail "$label container root maps to host root"

    find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$EVIDENCE_DIR/host-network-during-$label.txt"
    during_network_sha=$(sha256sum "$EVIDENCE_DIR/host-network-during-$label.txt" | awk '{ print $1 }')
    [ "$during_network_sha" = "$HOST_NETWORK_SHA" ] || fail "$label runtime changed host network interfaces"

    systemctl --machine="$MACHINE" is-active multi-user.target > "$EVIDENCE_DIR/$label-multi-user-target.txt"
}

stop_cleanly() {
    label=$1
    machinectl poweroff "$MACHINE" > "$EVIDENCE_DIR/$label-poweroff.txt"

    set +e
    wait "$NSPAWN_PID"
    exit_code=$?
    set -e
    NSPAWN_PID=

    printf '%s\n' "$exit_code" > "$EVIDENCE_DIR/$label-nspawn-exit.txt"
    [ "$exit_code" -eq 0 ] || fail "$label clean shutdown produced nspawn exit $exit_code"
    wait_machine_gone || fail "$label machine remained registered after clean shutdown"
}

force_failure() {
    leader=$(machinectl show "$MACHINE" -p Leader --value)
    case "$leader" in *[!0-9]*|'') fail 'forced-failure machine leader is invalid' ;; esac
    printf '%s\n' "$leader" > "$EVIDENCE_DIR/forced-failure-leader.txt"

    kill -KILL "$leader"
    set +e
    wait "$NSPAWN_PID"
    exit_code=$?
    set -e
    NSPAWN_PID=

    printf '%s\n' "$exit_code" > "$EVIDENCE_DIR/forced-failure-nspawn-exit.txt"
    [ "$exit_code" -ne 0 ] || fail 'forced guest PID 1 failure produced a zero nspawn exit'
    wait_machine_gone || fail 'machine remained registered after forced failure'
    FORCED_FAILURE_EXIT=$exit_code
}

bootstrap_generation 1
start_machine clean
capture_runtime clean
stop_cleanly clean
[ ! -e "$DESTINATION/var/lib/morimil-runtime/volatile-marker" ] || fail 'volatile /var marker persisted into the rootfs after shutdown'

start_machine forced-failure
run_in_machine /usr/bin/test ! -e /var/lib/morimil-runtime/volatile-marker
force_failure

[ "$(cat /proc/sys/kernel/random/boot_id)" = "$HOST_BOOT_ID" ] || fail 'host boot ID changed after forced failure'
[ "$(cat /proc/1/comm)" = systemd ] || fail 'host PID 1 changed after forced failure'
[ "$(sha256sum "$HOST_SENTINEL" | awk '{ print $1 }')" = "$HOST_SENTINEL_SHA" ] || fail 'host sentinel changed after forced failure'
systemctl is-active --quiet systemd-machined.service || fail 'systemd-machined failed after forced guest failure'

rm -rf "$DESTINATION" "$STATE_ROOT"
[ ! -e "$DESTINATION" ] || fail 'generation 1 rootfs destruction failed'
[ ! -e "$STATE_DIR" ] || fail 'generation 1 state destruction failed'

bootstrap_generation 2
start_machine rebuild
capture_runtime rebuild
stop_cleanly rebuild

GEN1_SHA=$(awk -F= '$1 == "MORIMIL_ROOTFS_SHA256" { print $2; exit }' "$EVIDENCE_DIR/generation-1-rootfs-source.env")
GEN2_SHA=$(awk -F= '$1 == "MORIMIL_ROOTFS_SHA256" { print $2; exit }' "$EVIDENCE_DIR/generation-2-rootfs-source.env")
[ -n "$GEN1_SHA" ] || fail 'generation 1 rootfs checksum is missing'
[ "$GEN1_SHA" = "$GEN2_SHA" ] || fail 'reconstructed rootfs checksum differs from generation 1'

grep -Fqx 'generation=1' "$EVIDENCE_DIR/clean-proof.env" || fail 'clean runtime proof generation mismatch'
grep -Fqx 'generation=2' "$EVIDENCE_DIR/rebuild-proof.env" || fail 'rebuild runtime proof generation mismatch'

find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$EVIDENCE_DIR/host-network-after.txt"
AFTER_NETWORK_SHA=$(sha256sum "$EVIDENCE_DIR/host-network-after.txt" | awk '{ print $1 }')
AFTER_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
AFTER_SENTINEL_SHA=$(sha256sum "$HOST_SENTINEL" | awk '{ print $1 }')

cat > "$EVIDENCE_DIR/host-after.env" <<EOF_HOST_AFTER
boot_id=$AFTER_BOOT_ID
sentinel_sha256=$AFTER_SENTINEL_SHA
network_sha256=$AFTER_NETWORK_SHA
net_namespace=$(readlink /proc/1/ns/net)
pid1_comm=$(cat /proc/1/comm)
architecture=$(uname -m)
EOF_HOST_AFTER

[ "$AFTER_BOOT_ID" = "$HOST_BOOT_ID" ] || fail 'host boot ID changed during runtime validation'
[ "$AFTER_SENTINEL_SHA" = "$HOST_SENTINEL_SHA" ] || fail 'host sentinel changed during runtime validation'
[ "$AFTER_NETWORK_SHA" = "$HOST_NETWORK_SHA" ] || fail 'host network interfaces changed during runtime validation'

rm -rf "$MACHINE_ROOT" "$STATE_ROOT"
rm -f "$TRUSTED_POLICY"
[ ! -e "$DESTINATION" ] || fail 'final rootfs cleanup failed'
[ ! -e "$STATE_DIR" ] || fail 'final state cleanup failed'
! machine_exists || fail 'machine remained registered after final cleanup'
[ ! -e "$TRUSTED_POLICY" ] || fail 'trusted nspawn policy cleanup failed'

cat > "$EVIDENCE_DIR/runtime-summary.env" <<EOF_SUMMARY
host_architecture=aarch64
clean_boot=yes
clean_shutdown=yes
forced_failure=yes
forced_failure_exit=$FORCED_FAILURE_EXIT
host_survived_failure=yes
reconstruction=yes
rebuild_boot=yes
private_users=yes
private_network=yes
root_read_only=yes
volatile_state=yes
no_new_privileges=yes
EOF_SUMMARY

cat > "$EVIDENCE_DIR/cleanup-status.env" <<'EOF_CLEANUP'
rootfs_removed=yes
state_removed=yes
machine_unregistered=yes
trusted_policy_removed=yes
EOF_CLEANUP

printf 'MORIMIL_ARCH_EXECUTOR_RUNTIME_VALIDATED=yes\n' > "$EVIDENCE_DIR/validation-status.env"
printf 'result=success\nstage=complete\n' > "$STATUS_FILE"
chmod 0644 "$STATUS_FILE" "$EVIDENCE_DIR"/*

sh "$ROOT_DIR/scripts/check-arch-executor-runtime-evidence.sh" "$EVIDENCE_DIR"

printf 'Pinned Arch executor runtime validation passed.\n'
printf 'The executor booted twice, survived a forced failure, and was removed.\n'
