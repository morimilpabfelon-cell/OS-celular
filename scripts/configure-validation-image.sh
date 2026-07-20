#!/bin/sh

set -eu
umask 022

TARGET_ROOT=${MORIMIL_IMAGE_ROOT:-/}

case "$TARGET_ROOT" in
    /*) ;;
    *)
        printf 'error: MORIMIL_IMAGE_ROOT must be an absolute path\n' >&2
        exit 1
        ;;
esac

mkdir -p \
    "$TARGET_ROOT/usr/local/sbin" \
    "$TARGET_ROOT/etc/systemd/system" \
    "$TARGET_ROOT/etc/systemd/system/multi-user.target.wants"

rm -f "$TARGET_ROOT/etc/resolv.conf"
cat > "$TARGET_ROOT/etc/resolv.conf" <<'RESOLV'
# Morimil validation image: QEMU networking is disabled.
RESOLV
chmod 0644 "$TARGET_ROOT/etc/resolv.conf"

cat > "$TARGET_ROOT/usr/local/sbin/morimil-boot-proof" <<'PROOF'
#!/bin/sh

set -eu

if systemctl is-active --quiet multi-user.target; then
    printf '%s\n' 'MORIMIL_BOOT_PROOF target=multi-user.target state=active' > /dev/console
    sync
    systemctl --no-block poweroff
    exit 0
fi

printf '%s\n' 'MORIMIL_BOOT_PROOF_FAILED target=multi-user.target state=inactive' > /dev/console
sync
systemctl --no-block poweroff
exit 1
PROOF
chmod 0755 "$TARGET_ROOT/usr/local/sbin/morimil-boot-proof"

cat > "$TARGET_ROOT/etc/systemd/system/morimil-boot-proof.service" <<'SERVICE'
[Unit]
Description=Emit Morimil QEMU boot proof and power off

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/morimil-boot-proof
TimeoutStartSec=30
SERVICE

cat > "$TARGET_ROOT/etc/systemd/system/morimil-boot-proof.timer" <<'TIMER'
[Unit]
Description=Run Morimil boot proof after multi-user startup

[Timer]
OnActiveSec=5s
AccuracySec=1s
Unit=morimil-boot-proof.service

[Install]
WantedBy=multi-user.target
TIMER

ln -sfn \
    ../morimil-boot-proof.timer \
    "$TARGET_ROOT/etc/systemd/system/multi-user.target.wants/morimil-boot-proof.timer"

printf '%s\n' 'morimil-validation' > "$TARGET_ROOT/etc/hostname"
