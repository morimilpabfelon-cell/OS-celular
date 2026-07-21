#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=${ARCH_ROOTFS_EVIDENCE_DIR:-$ROOT_DIR/build/arch-rootfs-release}
ROOTFS_URL=${ARCH_ROOTFS_URL:-https://mirror.math.princeton.edu/pub/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz}
SIGNATURE_URL=${ROOTFS_URL}.sig
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

for command_name in curl gpg sha256sum sha512sum bsdtar python3 awk wc date mktemp mkdir rm chmod; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

[ ! -e "$OUTPUT_DIR" ] || fail "evidence directory already exists: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chmod 0700 "$OUTPUT_DIR"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/morimil-arch-release.XXXXXX")
ARCHIVE=$WORK_DIR/rootfs.tar.gz
SIGNATURE=$WORK_DIR/rootfs.tar.gz.sig
GNUPGHOME=$WORK_DIR/gnupg

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup 0 HUP INT TERM

mkdir -m 0700 "$GNUPGHOME"

curl \
    --fail \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --tlsv1.2 \
    --dump-header "$OUTPUT_DIR/rootfs.headers" \
    --write-out 'effective_url=%{url_effective}\nhttp_code=%{http_code}\nsize_download=%{size_download}\ncontent_type=%{content_type}\n' \
    --output "$ARCHIVE" \
    "$ROOTFS_URL" \
    > "$OUTPUT_DIR/rootfs.transfer" \
    2> "$OUTPUT_DIR/rootfs.curl.log"

curl \
    --fail \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --tlsv1.2 \
    --dump-header "$OUTPUT_DIR/signature.headers" \
    --write-out 'effective_url=%{url_effective}\nhttp_code=%{http_code}\nsize_download=%{size_download}\ncontent_type=%{content_type}\n' \
    --output "$SIGNATURE" \
    "$SIGNATURE_URL" \
    > "$OUTPUT_DIR/signature.transfer" \
    2> "$OUTPUT_DIR/signature.curl.log"

gpg \
    --homedir "$GNUPGHOME" \
    --batch \
    --keyserver "$KEYSERVER" \
    --recv-keys "$SIGNING_FINGERPRINT" \
    > "$OUTPUT_DIR/key-import.log" 2>&1

gpg \
    --homedir "$GNUPGHOME" \
    --batch \
    --with-colons \
    --fingerprint "$SIGNING_FINGERPRINT" \
    > "$OUTPUT_DIR/key.txt"

ACTUAL_FINGERPRINT=$(awk -F: '$1 == "fpr" { print $10; exit }' "$OUTPUT_DIR/key.txt")
[ "$ACTUAL_FINGERPRINT" = "$SIGNING_FINGERPRINT" ] || fail 'imported signing key fingerprint does not match the pinned fingerprint'

gpg \
    --homedir "$GNUPGHOME" \
    --batch \
    --status-fd 1 \
    --verify "$SIGNATURE" "$ARCHIVE" \
    > "$OUTPUT_DIR/signature.status" 2> "$OUTPUT_DIR/signature.log"

grep -Fq '[GNUPG:] VALIDSIG ' "$OUTPUT_DIR/signature.status" || fail 'GnuPG did not report a valid detached signature'

ARCHIVE_SHA256=$(sha256sum "$ARCHIVE" | awk '{ print $1 }')
ARCHIVE_SHA512=$(sha512sum "$ARCHIVE" | awk '{ print $1 }')
ARCHIVE_SIZE=$(wc -c < "$ARCHIVE" | awk '{ print $1 }')
SIGNATURE_SHA256=$(sha256sum "$SIGNATURE" | awk '{ print $1 }')

bsdtar -tf "$ARCHIVE" > "$OUTPUT_DIR/archive-list.txt"
python3 "$ROOT_DIR/scripts/validate-rootfs-archive.py" < "$OUTPUT_DIR/archive-list.txt"
ARCHIVE_ENTRIES=$(wc -l < "$OUTPUT_DIR/archive-list.txt" | awk '{ print $1 }')
ARCHIVE_LIST_SHA256=$(sha256sum "$OUTPUT_DIR/archive-list.txt" | awk '{ print $1 }')

OS_RELEASE_PATH=$(awk '$0 == "etc/os-release" || $0 == "./etc/os-release" { print; exit }' "$OUTPUT_DIR/archive-list.txt")
PACMAN_PATH=$(awk '$0 == "usr/bin/pacman" || $0 == "./usr/bin/pacman" { print; exit }' "$OUTPUT_DIR/archive-list.txt")
[ -n "$OS_RELEASE_PATH" ] || fail 'archive does not contain /etc/os-release'
[ -n "$PACMAN_PATH" ] || fail 'archive does not contain /usr/bin/pacman'

bsdtar -xOf "$ARCHIVE" "$OS_RELEASE_PATH" > "$OUTPUT_DIR/os-release"
grep -Eq '^ID=archarm$|^ID=arch$' "$OUTPUT_DIR/os-release" || fail 'archive does not identify itself as Arch Linux ARM'

{
    printf 'curl='; curl --version | awk 'NR == 1 { print; exit }'
    printf 'gpg='; gpg --version | awk 'NR == 1 { print; exit }'
    printf 'bsdtar='; bsdtar --version | awk 'NR == 1 { print; exit }'
    printf 'python='; python3 --version
} > "$OUTPUT_DIR/environment.txt"

cat > "$OUTPUT_DIR/release.env" <<EOF
MORIMIL_ARCH_ROOTFS_URL=$ROOTFS_URL
MORIMIL_ARCH_ROOTFS_SIGNATURE_URL=$SIGNATURE_URL
MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT=$SIGNING_FINGERPRINT
MORIMIL_ARCH_ROOTFS_SHA256=$ARCHIVE_SHA256
MORIMIL_ARCH_ROOTFS_SHA512=$ARCHIVE_SHA512
MORIMIL_ARCH_ROOTFS_SIZE=$ARCHIVE_SIZE
MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256=$SIGNATURE_SHA256
MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES=$ARCHIVE_ENTRIES
MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256=$ARCHIVE_LIST_SHA256
MORIMIL_ARCH_ROOTFS_SIGNATURE_VERIFIED=yes
MORIMIL_ARCH_ROOTFS_OBSERVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 0644 "$OUTPUT_DIR"/*

printf 'Arch Linux ARM release inspected successfully.\n'
printf 'sha256=%s\n' "$ARCHIVE_SHA256"
printf 'size=%s\n' "$ARCHIVE_SIZE"
printf 'The rootfs archive was not published or executed.\n'
