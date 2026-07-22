#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
MACHINE=${ARCH_EXECUTOR_MACHINE:-morimil-arch}
ROOTFS=${ARCH_EXECUTOR_ROOTFS:-/var/lib/machines/$MACHINE}
STATE_DIR=${ARCH_EXECUTOR_STATE_DIR:-/var/lib/morimil/executors/arch}
PREPARED_FILE=$STATE_DIR/runtime-prepared.env

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

case "$MACHINE" in
    ''|*[!A-Za-z0-9_.-]*) fail 'ARCH_EXECUTOR_MACHINE contains unsupported characters' ;;
esac
case "$ROOTFS" in
    /*) ;;
    *) fail 'ARCH_EXECUTOR_ROOTFS must be absolute' ;;
esac
case "$STATE_DIR" in
    /*) ;;
    *) fail 'ARCH_EXECUTOR_STATE_DIR must be absolute' ;;
esac

[ "$(id -u)" -eq 0 ] || fail 'root privileges are required to prepare executor ownership'
for command_name in chmod id ln mkdir mv rm stat systemd-nspawn; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

[ -d "$ROOTFS" ] || fail "executor rootfs is missing: $ROOTFS"
[ -f "$ROOTFS/etc/morimil/rootfs-source.env" ] || fail 'executor rootfs is missing authenticated source metadata'
[ ! -e "$PREPARED_FILE" ] || fail "executor runtime is already prepared: $PREPARED_FILE"

UNIT_DIR=$ROOTFS/etc/systemd/system
TARGET_WANTS=$UNIT_DIR/morimil-executor.target.wants
READY_PROGRAM=$ROOTFS/usr/local/libexec/morimil-executor-ready
READY_SERVICE=$UNIT_DIR/morimil-executor-ready.service
PREPARED_TMP=$PREPARED_FILE.tmp
SHIFT_LOG=$STATE_DIR/ownership-shift.log
COMMITTED=0

cleanup() {
    if [ "$COMMITTED" -eq 0 ]; then
        rm -f "$PREPARED_TMP"
    fi
}
trap cleanup 0 HUP INT TERM

mkdir -p "$TARGET_WANTS" "$ROOTFS/usr/local/libexec" "$STATE_DIR"

cat > "$UNIT_DIR/morimil-executor.target" <<'EOF_TARGET'
[Unit]
Description=Morimil isolated Arch executor target
Requires=basic.target morimil-executor-ready.service
After=basic.target morimil-executor-ready.service
AllowIsolate=yes
EOF_TARGET
chmod 0644 "$UNIT_DIR/morimil-executor.target"

cat > "$READY_PROGRAM" <<'EOF_READY'
#!/bin/sh
set -eu
mkdir -p /run/morimil
interfaces=
for path in /sys/class/net/*; do
    [ -e "$path" ] || continue
    name=${path##*/}
    if [ -z "$interfaces" ]; then
        interfaces=$name
    else
        interfaces=$interfaces,$name
    fi
done
{
    printf 'pid1_comm='; cat /proc/1/comm
    printf 'network_interfaces=%s\n' "$interfaces"
} > /run/morimil/executor-ready.env
EOF_READY
chmod 0755 "$READY_PROGRAM"

cat > "$READY_SERVICE" <<'EOF_SERVICE'
[Unit]
Description=Mark the Morimil Arch executor ready
After=basic.target
Before=morimil-executor.target

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/morimil-executor-ready
RemainAfterExit=yes
NoNewPrivileges=yes

[Install]
WantedBy=morimil-executor.target
EOF_SERVICE
chmod 0644 "$READY_SERVICE"

ln -sfn ../morimil-executor-ready.service "$TARGET_WANTS/morimil-executor-ready.service"
ln -sfn morimil-executor.target "$UNIT_DIR/default.target"

for unit in \
    archlinux-keyring-wkd-sync.timer \
    systemd-networkd.service \
    systemd-networkd.socket \
    systemd-networkd-persistent-storage.service \
    systemd-networkd-resolve-hook.socket \
    systemd-networkd-varlink-metrics.socket \
    systemd-networkd-varlink.socket \
    systemd-resolved.service \
    systemd-resolved-monitor.socket \
    systemd-resolved-varlink.socket
do
    rm -f "$UNIT_DIR/$unit"
    ln -s /dev/null "$UNIT_DIR/$unit"
done

printf '6d6f72696d696c617263686578656375\n' > "$ROOTFS/etc/machine-id"
chmod 0644 "$ROOTFS/etc/machine-id"
printf '%s\n' "$MACHINE" > "$ROOTFS/etc/hostname"
chmod 0644 "$ROOTFS/etc/hostname"

systemd-nspawn \
    --quiet \
    --machine="$MACHINE-prepare" \
    --directory="$ROOTFS" \
    --settings=no \
    --register=no \
    --private-network \
    --private-users=pick \
    --private-users-ownership=chown \
    --link-journal=no \
    --resolv-conf=off \
    --timezone=off \
    /usr/bin/true \
    > "$SHIFT_LOG" 2>&1

UID_SHIFT=$(stat -c '%u' "$ROOTFS")
case "$UID_SHIFT" in
    ''|*[!0-9]*) fail 'prepared rootfs UID shift is invalid' ;;
esac
[ "$UID_SHIFT" -ge 65536 ] || fail 'prepared rootfs UID shift is unexpectedly small'
[ $((UID_SHIFT % 65536)) -eq 0 ] || fail 'prepared rootfs UID shift is not aligned to 65536'

cat > "$PREPARED_TMP" <<EOF_PREPARED
MORIMIL_ARCH_EXECUTOR_MACHINE=$MACHINE
MORIMIL_ARCH_EXECUTOR_ROOTFS=$ROOTFS
MORIMIL_ARCH_EXECUTOR_UID_SHIFT=$UID_SHIFT
MORIMIL_ARCH_EXECUTOR_TARGET=morimil-executor.target
MORIMIL_ARCH_EXECUTOR_NETWORK=private-loopback-only
MORIMIL_ARCH_EXECUTOR_ROOT_READ_ONLY=yes
MORIMIL_ARCH_EXECUTOR_VOLATILE_STATE=yes
EOF_PREPARED
chmod 0644 "$PREPARED_TMP" "$SHIFT_LOG"
mv "$PREPARED_TMP" "$PREPARED_FILE"
COMMITTED=1

printf 'Arch executor rootfs prepared at %s\n' "$ROOTFS"
printf 'UID shift: %s\n' "$UID_SHIFT"
printf 'The executor was not started.\n'
