#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
PIN_FILE=${ARCH_ROOTFS_PIN_FILE:-$ROOT_DIR/config/arch-rootfs-release.env}
MACHINE_ROOT=${ARCH_ROOTFS_MACHINE_ROOT:-/var/lib/machines}
STATE_ROOT=${ARCH_ROOTFS_STATE_ROOT:-/var/lib/morimil/executors}
DESTINATION=${ARCH_ROOTFS_DESTINATION:-$MACHINE_ROOT/morimil-arch}
STATE_DIR=${ARCH_ROOTFS_STATE_DIR:-$STATE_ROOT/arch}
KEYSERVER=${ARCH_ROOTFS_KEYSERVER:-hkps://keyserver.ubuntu.com}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for command_name in curl gpg sha256sum sha512sum bsdtar python3 mktemp awk wc id mv rm mkdir chmod grep; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

[ -f "$PIN_FILE" ] || fail "Arch rootfs pin is missing: $PIN_FILE"
sh "$ROOT_DIR/scripts/check-arch-rootfs-pin.sh" "$PIN_FILE" >/dev/null

pin_value() {
    key=$1
    value=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PIN_FILE")
    [ -n "$value" ] || fail "missing Arch rootfs pin value: $key"
    printf '%s\n' "$value"
}

PIN_URL=$(pin_value MORIMIL_ARCH_ROOTFS_URL)
PIN_SIGNATURE_URL=$(pin_value MORIMIL_ARCH_ROOTFS_SIGNATURE_URL)
PIN_FINGERPRINT=$(pin_value MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT)
PIN_SHA256=$(pin_value MORIMIL_ARCH_ROOTFS_SHA256)
PIN_SHA512=$(pin_value MORIMIL_ARCH_ROOTFS_SHA512)
PIN_SIZE=$(pin_value MORIMIL_ARCH_ROOTFS_SIZE)
PIN_SIGNATURE_SHA256=$(pin_value MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256)
PIN_ARCHIVE_ENTRIES=$(pin_value MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES)
PIN_ARCHIVE_LIST_SHA256=$(pin_value MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256)

if [ "${ARCH_ROOTFS_URL+x}" = x ]; then
    ROOTFS_URL=$ARCH_ROOTFS_URL
    SIGNATURE_URL=${ARCH_ROOTFS_SIGNATURE_URL:-$ROOTFS_URL.sig}
else
    ROOTFS_URL=$PIN_URL
    SIGNATURE_URL=$PIN_SIGNATURE_URL
fi

EXPECTED_SHA256=${ARCH_ROOTFS_EXPECTED_SHA256:-$PIN_SHA256}
EXPECTED_SHA512=${ARCH_ROOTFS_EXPECTED_SHA512:-$PIN_SHA512}
EXPECTED_SIZE=${ARCH_ROOTFS_EXPECTED_SIZE:-$PIN_SIZE}
EXPECTED_SIGNATURE_SHA256=${ARCH_ROOTFS_EXPECTED_SIGNATURE_SHA256:-$PIN_SIGNATURE_SHA256}
EXPECTED_ARCHIVE_ENTRIES=${ARCH_ROOTFS_EXPECTED_ARCHIVE_ENTRIES:-$PIN_ARCHIVE_ENTRIES}
EXPECTED_ARCHIVE_LIST_SHA256=${ARCH_ROOTFS_EXPECTED_ARCHIVE_LIST_SHA256:-$PIN_ARCHIVE_LIST_SHA256}
SIGNING_FINGERPRINT=$PIN_FINGERPRINT

case "$ROOTFS_URL" in
    https://*) ;;
    *) fail 'ARCH_ROOTFS_URL must use HTTPS' ;;
esac
[ "$SIGNATURE_URL" = "$ROOTFS_URL.sig" ] || fail 'ARCH_ROOTFS_SIGNATURE_URL must equal rootfs URL plus .sig'

case "$KEYSERVER" in
    hkps://*) ;;
    *) fail 'ARCH_ROOTFS_KEYSERVER must use HKPS' ;;
esac

validate_hex() {
    name=$1
    value=$2
    length=$3
    case "$value" in *[!0-9a-f]*|'') fail "$name must be lowercase hexadecimal" ;; esac
    [ "${#value}" -eq "$length" ] || fail "$name has an invalid length"
}

validate_hex 'expected rootfs SHA-256' "$EXPECTED_SHA256" 64
validate_hex 'expected rootfs SHA-512' "$EXPECTED_SHA512" 128
validate_hex 'expected signature SHA-256' "$EXPECTED_SIGNATURE_SHA256" 64
validate_hex 'expected archive-list SHA-256' "$EXPECTED_ARCHIVE_LIST_SHA256" 64

case "$EXPECTED_SIZE" in *[!0-9]*|'') fail 'expected rootfs size must be numeric' ;; esac
case "$EXPECTED_ARCHIVE_ENTRIES" in *[!0-9]*|'') fail 'expected archive entry count must be numeric' ;; esac

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
ARCHIVE_LIST=$WORK_DIR/archive-list.txt
METADATA_TMP=$STATE_DIR/rootfs-source.env.tmp
PUBLISHED=0
COMMITTED=0

cleanup() {
    rm -rf "$WORK_DIR"
    if [ "$COMMITTED" -eq 0 ]; then
        rm -rf "$STAGE_DIR"
        rm -f "$METADATA_TMP"
        if [ "$PUBLISHED" -eq 1 ]; then
            rm -rf "$DESTINATION"
        fi
    fi
}
trap cleanup 0 HUP INT TERM

mkdir -m 0700 "$GNUPGHOME"

curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$ARCHIVE" "$ROOTFS_URL"
curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$SIGNATURE" "$SIGNATURE_URL"

gpg --homedir "$GNUPGHOME" --batch --keyserver "$KEYSERVER" --recv-keys "$SIGNING_FINGERPRINT"
gpg --homedir "$GNUPGHOME" --batch --with-colons --fingerprint "$SIGNING_FINGERPRINT" > "$WORK_DIR/fingerprint.txt"
ACTUAL_FINGERPRINT=$(awk -F: '$1 == "fpr" { print $10; exit }' "$WORK_DIR/fingerprint.txt")
[ "$ACTUAL_FINGERPRINT" = "$SIGNING_FINGERPRINT" ] || fail 'the imported Arch Linux ARM signing key fingerprint does not match the pinned fingerprint'

gpg --homedir "$GNUPGHOME" --batch --verify "$SIGNATURE" "$ARCHIVE"

ACTUAL_SIGNATURE_SHA256=$(sha256sum "$SIGNATURE" | awk '{ print $1 }')
[ "$ACTUAL_SIGNATURE_SHA256" = "$EXPECTED_SIGNATURE_SHA256" ] || fail "signature SHA-256 mismatch: expected $EXPECTED_SIGNATURE_SHA256, received $ACTUAL_SIGNATURE_SHA256"

ACTUAL_SHA256=$(sha256sum "$ARCHIVE" | awk '{ print $1 }')
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "rootfs SHA-256 mismatch: expected $EXPECTED_SHA256, received $ACTUAL_SHA256"
ACTUAL_SHA512=$(sha512sum "$ARCHIVE" | awk '{ print $1 }')
[ "$ACTUAL_SHA512" = "$EXPECTED_SHA512" ] || fail 'rootfs SHA-512 mismatch'
ACTUAL_SIZE=$(wc -c < "$ARCHIVE" | awk '{ print $1 }')
[ "$ACTUAL_SIZE" = "$EXPECTED_SIZE" ] || fail "rootfs size mismatch: expected $EXPECTED_SIZE, received $ACTUAL_SIZE"

bsdtar -tf "$ARCHIVE" > "$ARCHIVE_LIST"
python3 "$ROOT_DIR/scripts/validate-rootfs-archive.py" < "$ARCHIVE_LIST"
ACTUAL_ARCHIVE_ENTRIES=$(wc -l < "$ARCHIVE_LIST" | awk '{ print $1 }')
[ "$ACTUAL_ARCHIVE_ENTRIES" = "$EXPECTED_ARCHIVE_ENTRIES" ] || fail "archive entry count mismatch: expected $EXPECTED_ARCHIVE_ENTRIES, received $ACTUAL_ARCHIVE_ENTRIES"
ACTUAL_ARCHIVE_LIST_SHA256=$(sha256sum "$ARCHIVE_LIST" | awk '{ print $1 }')
[ "$ACTUAL_ARCHIVE_LIST_SHA256" = "$EXPECTED_ARCHIVE_LIST_SHA256" ] || fail 'archive list SHA-256 mismatch'

bsdtar --numeric-owner --acls --xattrs -xpf "$ARCHIVE" -C "$STAGE_DIR"

if [ -f "$STAGE_DIR/usr/lib/os-release" ]; then
    OS_RELEASE=$STAGE_DIR/usr/lib/os-release
else
    OS_RELEASE=$STAGE_DIR/etc/os-release
fi
[ -f "$OS_RELEASE" ] || fail 'extracted rootfs is missing os-release'
[ -x "$STAGE_DIR/usr/bin/pacman" ] || fail 'extracted rootfs is missing executable /usr/bin/pacman'
grep -Eq '^ID=archarm$|^ID=arch$' "$OS_RELEASE" || fail 'extracted rootfs does not identify itself as Arch Linux ARM'

mkdir -p "$STAGE_DIR/etc/morimil"
cat > "$STAGE_DIR/etc/morimil/rootfs-source.env" <<EOF
MORIMIL_ROOTFS_URL=$ROOTFS_URL
MORIMIL_ROOTFS_SIGNATURE_URL=$SIGNATURE_URL
MORIMIL_ROOTFS_SIGNING_FINGERPRINT=$SIGNING_FINGERPRINT
MORIMIL_ROOTFS_SHA256=$ACTUAL_SHA256
MORIMIL_ROOTFS_SHA512=$ACTUAL_SHA512
MORIMIL_ROOTFS_SIZE=$ACTUAL_SIZE
MORIMIL_ROOTFS_SIGNATURE_SHA256=$ACTUAL_SIGNATURE_SHA256
MORIMIL_ROOTFS_ARCHIVE_ENTRIES=$ACTUAL_ARCHIVE_ENTRIES
MORIMIL_ROOTFS_ARCHIVE_LIST_SHA256=$ACTUAL_ARCHIVE_LIST_SHA256
EOF
chmod 0644 "$STAGE_DIR/etc/morimil/rootfs-source.env"

cat > "$METADATA_TMP" <<EOF
MORIMIL_ROOTFS_URL=$ROOTFS_URL
MORIMIL_ROOTFS_SIGNATURE_URL=$SIGNATURE_URL
MORIMIL_ROOTFS_SIGNING_FINGERPRINT=$SIGNING_FINGERPRINT
MORIMIL_ROOTFS_SHA256=$ACTUAL_SHA256
MORIMIL_ROOTFS_SHA512=$ACTUAL_SHA512
MORIMIL_ROOTFS_SIZE=$ACTUAL_SIZE
MORIMIL_ROOTFS_SIGNATURE_SHA256=$ACTUAL_SIGNATURE_SHA256
MORIMIL_ROOTFS_ARCHIVE_ENTRIES=$ACTUAL_ARCHIVE_ENTRIES
MORIMIL_ROOTFS_ARCHIVE_LIST_SHA256=$ACTUAL_ARCHIVE_LIST_SHA256
MORIMIL_ROOTFS_DESTINATION=$DESTINATION
EOF
chmod 0644 "$METADATA_TMP"

mv "$STAGE_DIR" "$DESTINATION"
PUBLISHED=1
mv "$METADATA_TMP" "$STATE_DIR/rootfs-source.env"
COMMITTED=1

printf 'Arch Linux ARM rootfs published atomically at %s\n' "$DESTINATION"
printf 'The container was not started. Runtime isolation remains a separate validation step.\n'
