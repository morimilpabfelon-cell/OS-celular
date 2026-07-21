#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

REPOSITORY_ROOT=$SCRIPT_DIR/../..
CONFIGURE_SCRIPT=$REPOSITORY_ROOT/scripts/configure-validation-image.sh
TEST_TMP=$(mktemp -d /tmp/morimil-image-configuration.XXXXXX)
TARGET_ROOT=$TEST_TMP/root
EXPECTED_RESOLV=$TEST_TMP/expected-resolv.conf

trap 'rm -rf "$TEST_TMP"' 0
mkdir -p "$TARGET_ROOT/etc" "$TARGET_ROOT/run/systemd/resolve"

printf '%s\n' 'nameserver 192.0.2.1' > "$TARGET_ROOT/run/systemd/resolve/stub-resolv.conf"
ln -s /run/systemd/resolve/stub-resolv.conf "$TARGET_ROOT/etc/resolv.conf"

cat > "$EXPECTED_RESOLV" <<'RESOLV'
# Morimil validation image: QEMU networking is disabled.
RESOLV

MORIMIL_IMAGE_ROOT=$TARGET_ROOT sh "$CONFIGURE_SCRIPT"

if [ ! -f "$TARGET_ROOT/etc/resolv.conf" ] || [ -L "$TARGET_ROOT/etc/resolv.conf" ]; then
    printf 'error: resolver configuration was not replaced by a regular file\n' >&2
    exit 1
fi

cmp "$EXPECTED_RESOLV" "$TARGET_ROOT/etc/resolv.conf"

if [ "$(stat -c '%a' "$TARGET_ROOT/etc/resolv.conf")" != 644 ]; then
    printf 'error: resolver configuration mode is not 0644\n' >&2
    exit 1
fi

grep -Fqx -- 'morimil-validation' "$TARGET_ROOT/etc/hostname"

if [ ! -x "$TARGET_ROOT/usr/local/sbin/morimil-boot-proof" ]; then
    printf 'error: boot proof executable was not installed\n' >&2
    exit 1
fi

if [ "$(readlink "$TARGET_ROOT/etc/systemd/system/multi-user.target.wants/morimil-boot-proof.timer")" != ../morimil-boot-proof.timer ]; then
    printf 'error: boot proof timer link has an unexpected target\n' >&2
    exit 1
fi

printf '%s\n' 'nameserver 198.51.100.1' > "$TARGET_ROOT/etc/resolv.conf"
MORIMIL_IMAGE_ROOT=$TARGET_ROOT sh "$CONFIGURE_SCRIPT"
cmp "$EXPECTED_RESOLV" "$TARGET_ROOT/etc/resolv.conf"

printf 'Validation image configuration contract passed.\n'
