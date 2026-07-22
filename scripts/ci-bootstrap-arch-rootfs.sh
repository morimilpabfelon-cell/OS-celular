#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT_DIR/build/arch-rootfs-bootstrap}
PIN_FILE=${ARCH_ROOTFS_PIN_FILE:-$ROOT_DIR/config/arch-rootfs-release.env}
MACHINE_ROOT=$BUILD_DIR/machines
STATE_ROOT=$BUILD_DIR/state
DESTINATION=$MACHINE_ROOT/morimil-arch
STATE_DIR=$STATE_ROOT/arch
EVIDENCE_DIR=$BUILD_DIR/evidence

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail 'real Arch rootfs bootstrap validation must run as root'
[ ! -e "$BUILD_DIR" ] || fail "build directory already exists: $BUILD_DIR"

for command_name in file readelf find du sha256sum awk wc cp rm mkdir chmod; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

mkdir -p "$EVIDENCE_DIR"
chmod 0700 "$EVIDENCE_DIR"

cleanup() {
    rm -rf "$MACHINE_ROOT" "$STATE_ROOT"
}
trap cleanup 0 HUP INT TERM

sh "$ROOT_DIR/scripts/check-arch-rootfs-pin.sh" "$PIN_FILE" > "$EVIDENCE_DIR/pin-validation.txt"

ARCH_ROOTFS_PIN_FILE=$PIN_FILE \
ARCH_ROOTFS_MACHINE_ROOT=$MACHINE_ROOT \
ARCH_ROOTFS_STATE_ROOT=$STATE_ROOT \
ARCH_ROOTFS_DESTINATION=$DESTINATION \
ARCH_ROOTFS_STATE_DIR=$STATE_DIR \
sh "$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh" > "$EVIDENCE_DIR/bootstrap.log" 2>&1

[ -d "$DESTINATION" ] || fail 'bootstrap did not publish the rootfs destination'
[ -x "$DESTINATION/usr/bin/pacman" ] || fail 'published rootfs lacks executable pacman'
[ -f "$DESTINATION/etc/morimil/rootfs-source.env" ] || fail 'published rootfs lacks internal source metadata'
[ -f "$STATE_DIR/rootfs-source.env" ] || fail 'bootstrap did not publish external source metadata'

pin_value() {
    key=$1
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PIN_FILE"
}

PIN_SHA256=$(pin_value MORIMIL_ARCH_ROOTFS_SHA256)
PIN_SHA512=$(pin_value MORIMIL_ARCH_ROOTFS_SHA512)
PIN_SIZE=$(pin_value MORIMIL_ARCH_ROOTFS_SIZE)
PIN_SIGNATURE_SHA256=$(pin_value MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256)
PIN_ENTRIES=$(pin_value MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES)
PIN_LIST_SHA256=$(pin_value MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256)

for metadata in "$DESTINATION/etc/morimil/rootfs-source.env" "$STATE_DIR/rootfs-source.env"; do
    grep -Fqx "MORIMIL_ROOTFS_SHA256=$PIN_SHA256" "$metadata" || fail 'published SHA-256 does not match pin'
    grep -Fqx "MORIMIL_ROOTFS_SHA512=$PIN_SHA512" "$metadata" || fail 'published SHA-512 does not match pin'
    grep -Fqx "MORIMIL_ROOTFS_SIZE=$PIN_SIZE" "$metadata" || fail 'published size does not match pin'
    grep -Fqx "MORIMIL_ROOTFS_SIGNATURE_SHA256=$PIN_SIGNATURE_SHA256" "$metadata" || fail 'published signature checksum does not match pin'
    grep -Fqx "MORIMIL_ROOTFS_ARCHIVE_ENTRIES=$PIN_ENTRIES" "$metadata" || fail 'published archive entry count does not match pin'
    grep -Fqx "MORIMIL_ROOTFS_ARCHIVE_LIST_SHA256=$PIN_LIST_SHA256" "$metadata" || fail 'published archive list checksum does not match pin'
done

grep -Fqx "MORIMIL_ROOTFS_DESTINATION=$DESTINATION" "$STATE_DIR/rootfs-source.env" || fail 'external metadata records an unexpected destination'

if [ -f "$DESTINATION/usr/lib/os-release" ]; then
    OS_RELEASE=$DESTINATION/usr/lib/os-release
else
    OS_RELEASE=$DESTINATION/etc/os-release
fi
[ -f "$OS_RELEASE" ] || fail 'published rootfs lacks os-release'
grep -Eq '^ID=archarm$|^ID=arch$' "$OS_RELEASE" || fail 'published rootfs does not identify Arch Linux ARM'

ROOTFS_ENTRIES=$(find "$DESTINATION" -xdev -printf '.\n' | wc -l | awk '{ print $1 }')
[ "$ROOTFS_ENTRIES" -ge 10000 ] || fail 'published rootfs contains unexpectedly few filesystem entries'
ROOTFS_BYTES=$(du -sb "$DESTINATION" | awk '{ print $1 }')
[ "$ROOTFS_BYTES" -ge 100000000 ] || fail 'published rootfs consumes unexpectedly little storage'

file "$DESTINATION/usr/bin/pacman" > "$EVIDENCE_DIR/pacman-file.txt"
grep -Eqi 'aarch64|ARM aarch64' "$EVIDENCE_DIR/pacman-file.txt" || fail 'pacman is not identified as an AArch64 executable'
readelf -h "$DESTINATION/usr/bin/pacman" > "$EVIDENCE_DIR/pacman-elf-header.txt"
grep -Eq 'Machine:[[:space:]]+AArch64' "$EVIDENCE_DIR/pacman-elf-header.txt" || fail 'pacman ELF machine is not AArch64'

cp "$PIN_FILE" "$EVIDENCE_DIR/pin.env"
cp "$STATE_DIR/rootfs-source.env" "$EVIDENCE_DIR/rootfs-source.env"
cp "$OS_RELEASE" "$EVIDENCE_DIR/os-release"
sha256sum "$EVIDENCE_DIR/pin.env" > "$EVIDENCE_DIR/pin.env.sha256"
sha256sum "$EVIDENCE_DIR/rootfs-source.env" > "$EVIDENCE_DIR/rootfs-source.env.sha256"
sha256sum "$EVIDENCE_DIR/os-release" > "$EVIDENCE_DIR/os-release.sha256"

{
    printf 'rootfs_filesystem_entries=%s\n' "$ROOTFS_ENTRIES"
    printf 'rootfs_extracted_bytes=%s\n' "$ROOTFS_BYTES"
    printf 'rootfs_archive_sha256=%s\n' "$PIN_SHA256"
    printf 'rootfs_archive_size=%s\n' "$PIN_SIZE"
} > "$EVIDENCE_DIR/rootfs-inspection.txt"

{
    printf 'kernel='; uname -srmo
    printf 'file='; file --version | awk 'NR == 1 { print; exit }'
    printf 'readelf='; readelf --version | awk 'NR == 1 { print; exit }'
    printf 'bsdtar='; bsdtar --version | awk 'NR == 1 { print; exit }'
    printf 'gpg='; gpg --version | awk 'NR == 1 { print; exit }'
    printf 'curl='; curl --version | awk 'NR == 1 { print; exit }'
} > "$EVIDENCE_DIR/environment.txt"

rm -rf "$MACHINE_ROOT" "$STATE_ROOT"
[ ! -e "$DESTINATION" ] || fail 'rootfs cleanup failed'
[ ! -e "$STATE_DIR" ] || fail 'state cleanup failed'
printf 'rootfs_removed=yes\nstate_removed=yes\n' > "$EVIDENCE_DIR/cleanup-status.txt"
printf 'MORIMIL_ARCH_ROOTFS_BOOTSTRAP_VALIDATED=yes\n' > "$EVIDENCE_DIR/validation-status.txt"
chmod 0644 "$EVIDENCE_DIR"/*

printf 'Pinned Arch Linux ARM rootfs bootstrap validation passed.\n'
printf 'The rootfs was removed and was never started.\n'
