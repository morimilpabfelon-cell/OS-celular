#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
ROOTFS_URL=${ARCH_ROOTFS_URL:-https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
SIGNATURE_URL=${ROOTFS_URL}.sig
EXPECTED_SHA256=${ARCH_ROOTFS_EXPECTED_SHA256:-}
MACHINE_ROOT=${ARCH_ROOTFS_MACHINE_ROOT:-/var/lib/machines}
STATE_ROOT=${ARCH_ROOTFS_STATE_ROOT:-/var/lib/morimil/executors}
DESTINATION=${ARCH_ROOTFS_DESTINATION:-$MACHINE_ROOT/morimil-arch}
STATE_DIR=${ARCH_ROOTFS_STATE_DIR:-$STATE_ROOT/arch}
KEYSERVER=${ARCH_ROOTFS_KEYSERVER:-hkps://keyserver.ubuntu.com}
SIGNING_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

case "$ROOTFS_URL" in
    https://*) ;;
    *) fail 'ARCH_ROOTFS_URL must use HTTPS' ;;
esac

case "$KEYSERVER" in
    hkps://*) ;;
    *) fail 'ARCH_ROOTFS_KEYSERVER must use HKPS' ;;
esac

case "$EXPECTED_SHA256" in
    *[!0-9a-f]*|'') fail 'ARCH_ROOTFS_EXPECTED_SHA256 must be a lowercase 64-character hexadecimal digest' ;;
esac
[ "${#EXPECTED_SHA256}" -eq 64 ] || fail 'ARCH_ROOTFS_EXPECTED_SHA256 must contain exactly 64 hexadecimal characters'

case "$MACHINE_ROOT" in
    /*) ;;
    *) fail 'ARCH_ROOTFS_MACHINE_ROOT must be absolute' ;;
esac
case "$STATE_ROOT" in
    /*) ;;
    *) fail 'ARCH_ROOTFS_STATE_ROOT must be absolute' ;;
esac
case "$DESTINATION" in
    "$MACHINE_ROOT"/*) ;;
    *) fail 'ARCH_ROOTFS_DESTINATION must be below ARCH_ROOTFS_MACHINE_ROOT' ;;
esac
[ "$DESTINATION" != "$MACHINE_ROOT/" ] || fail 'ARCH_ROOTFS_DESTINATION must name one executor'
case "$DESTINATION" in
    *'/../'*|*'/..'|*'/./'*|*'/.' ) fail 'ARCH_ROOTFS_DESTINATION must not contain dot path components' ;;
esac

case "$STATE_DIR" in
    "$STATE_ROOT"/*) ;;
    *) fail 'ARCH_ROOTFS_STATE_DIR must be below ARCH_ROOTFS_STATE_ROOT' ;;
esac
case "$STATE_DIR" in
    *'/../'*|*'/..'|*'/./'*|*'/.' ) fail 'ARCH_ROOTFS_STATE_DIR must not contain dot path components' ;;
esac

for command_name in curl gpg sha256sum bsdtar python3 mktemp awk id; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

[ "$(id -u)" -eq 0 ] || fail 'root privileges are required to preserve ownership, ACLs and extended attributes'
[ ! -e "$DESTINATION" ] || fail "destination already exists: $DESTINATION"
[ ! -e "$STATE_DIR/rootfs-source.env" ] || fail "state metadata already exists: $STATE_DIR/rootfs-source.env"

DESTINATION_PARENT=${DESTINATION%/*}
mkdir -p "$DESTINATION_PARENT" "$STATE_DIR"
WORK_DIR=$(mktemp -d "$DESTINATION_PARENT/.morimil-arch-download.XXXXXX")
STAGE_DIR=$(mktemp -d "$DESTINATION_PARENT/.morimil-arch-stage.XXXXXX")
ARCHIVE=$WORK_DIR/rootfs.tar.gz
SIGNATURE=$WORK_DIR/rootfs.tar.gz.sig
GNUPGHOME=$WORK_DIR/gnupg
PUBLISHED=0
trap 'rm -rf "$WORK_DIR"; if [ "$PUBLISHED" -eq 0 ]; then rm -rf "$STAGE_DIR"; fi' 0 HUP INT TERM

mkdir -m 0700 "$GNUPGHOME"

curl --fail --location --proto '=https' --tlsv1.2 --output "$ARCHIVE" "$ROOTFS_URL"
curl --fail --location --proto '=https' --tlsv1.2 --output "$SIGNATURE" "$SIGNATURE_URL"

gpg --homedir "$GNUPGHOME" --batch --keyserver "$KEYSERVER" --recv-keys "$SIGNING_FINGERPRINT"
gpg --homedir "$GNUPGHOME" --batch --with-colons --fingerprint "$SIGNING_FINGERPRINT" > "$WORK_DIR/fingerprint.txt"
ACTUAL_FINGERPRINT=$(awk -F: '$1 == "fpr" { print $10; exit }' "$WORK_DIR/fingerprint.txt")
[ "$ACTUAL_FINGERPRINT" = "$SIGNING_FINGERPRINT" ] || fail 'the imported Arch Linux ARM signing key fingerprint does not match the pinned fingerprint'

gpg --homedir "$GNUPGHOME" --batch --verify "$SIGNATURE" "$ARCHIVE"

sha256sum "$ARCHIVE" > "$WORK_DIR/rootfs.sha256"
ACTUAL_SHA256=$(awk '{ print $1 }' "$WORK_DIR/rootfs.sha256")
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "rootfs SHA-256 mismatch: expected $EXPECTED_SHA256, received $ACTUAL_SHA256"

bsdtar -tf "$ARCHIVE" | python3 "$ROOT_DIR/scripts/validate-rootfs-archive.py"
bsdtar --numeric-owner --acls --xattrs -xpf "$ARCHIVE" -C "$STAGE_DIR"

[ -f "$STAGE_DIR/etc/os-release" ] || fail 'extracted rootfs is missing /etc/os-release'
[ -x "$STAGE_DIR/usr/bin/pacman" ] || fail 'extracted rootfs is missing executable /usr/bin/pacman'
grep -Eq '^ID=archarm$|^ID=arch$' "$STAGE_DIR/etc/os-release" || fail 'extracted rootfs does not identify itself as Arch Linux ARM'

mkdir -p "$STAGE_DIR/etc/morimil"
cat > "$STAGE_DIR/etc/morimil/rootfs-source.env" <<EOF
MORIMIL_ROOTFS_URL=$ROOTFS_URL
MORIMIL_ROOTFS_SIGNATURE_URL=$SIGNATURE_URL
MORIMIL_ROOTFS_SIGNING_FINGERPRINT=$SIGNING_FINGERPRINT
MORIMIL_ROOTFS_SHA256=$ACTUAL_SHA256
EOF
chmod 0644 "$STAGE_DIR/etc/morimil/rootfs-source.env"

mv "$STAGE_DIR" "$DESTINATION"
PUBLISHED=1

METADATA_TMP=$STATE_DIR/rootfs-source.env.tmp
cat > "$METADATA_TMP" <<EOF
MORIMIL_ROOTFS_URL=$ROOTFS_URL
MORIMIL_ROOTFS_SIGNATURE_URL=$SIGNATURE_URL
MORIMIL_ROOTFS_SIGNING_FINGERPRINT=$SIGNING_FINGERPRINT
MORIMIL_ROOTFS_SHA256=$ACTUAL_SHA256
MORIMIL_ROOTFS_DESTINATION=$DESTINATION
EOF
chmod 0644 "$METADATA_TMP"
mv "$METADATA_TMP" "$STATE_DIR/rootfs-source.env"

printf 'Arch Linux ARM rootfs published atomically at %s\n' "$DESTINATION"
printf 'The container was not started. Runtime isolation remains a separate validation step.\n'
