#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
CHECK=$ROOT_DIR/scripts/check-arch-rootfs-release-evidence.sh
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

expect_reject() {
    name=$1
    directory=$2
    if sh "$CHECK" "$directory" >/dev/null 2>&1; then
        fail "$name was accepted"
    fi
}

make_evidence() {
    directory=$1
    mkdir -p "$directory"
    : > "$directory/rootfs.headers"
    : > "$directory/rootfs.transfer"
    : > "$directory/key.txt"
    : > "$directory/signature.log"
    : > "$directory/environment.txt"
    printf '[GNUPG:] VALIDSIG 68B3537F39A313B3E574D06777193F152BDBE6A6\n' > "$directory/signature.status"
    printf 'ID=archarm\n' > "$directory/os-release"
    awk 'BEGIN { for (i = 1; i <= 10000; i++) print "usr/lib/morimil-fixture-" i }' > "$directory/archive-list.txt"
    list_sha=$(sha256sum "$directory/archive-list.txt" | awk '{ print $1 }')
    cat > "$directory/release.env" <<EOF
MORIMIL_ARCH_ROOTFS_URL=https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
MORIMIL_ARCH_ROOTFS_SIGNATURE_URL=https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6
MORIMIL_ARCH_ROOTFS_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
MORIMIL_ARCH_ROOTFS_SHA512=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
MORIMIL_ARCH_ROOTFS_SIZE=100000000
MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES=10000
MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256=$list_sha
MORIMIL_ARCH_ROOTFS_SIGNATURE_VERIFIED=yes
MORIMIL_ARCH_ROOTFS_OBSERVED_AT=2026-07-21T23:59:59Z
EOF
}

VALID=$TMP_DIR/valid
make_evidence "$VALID"
sh "$CHECK" "$VALID" >/dev/null

HTTP=$TMP_DIR/http
cp -R "$VALID" "$HTTP"
sed -i 's#https://os.archlinuxarm.org#http://os.archlinuxarm.org#' "$HTTP/release.env"
expect_reject 'HTTP evidence URL' "$HTTP"

FINGERPRINT=$TMP_DIR/fingerprint
cp -R "$VALID" "$FINGERPRINT"
sed -i 's/68B3537F39A313B3E574D06777193F152BDBE6A6/0000000000000000000000000000000000000000/' "$FINGERPRINT/release.env"
expect_reject 'incorrect signing fingerprint' "$FINGERPRINT"

LIST_HASH=$TMP_DIR/list-hash
cp -R "$VALID" "$LIST_HASH"
printf 'mutation\n' >> "$LIST_HASH/archive-list.txt"
expect_reject 'mutated archive list' "$LIST_HASH"

ARCHIVE=$TMP_DIR/archive
cp -R "$VALID" "$ARCHIVE"
: > "$ARCHIVE/rootfs.tar.gz"
expect_reject 'retained rootfs archive' "$ARCHIVE"

printf 'Arch rootfs release evidence contract tests passed.\n'
