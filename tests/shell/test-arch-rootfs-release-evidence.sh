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
    printf 'effective_url=https://mirror.example/rootfs.tar.gz\nhttp_code=200\nsize_download=100000000\ncontent_type=application/octet-stream\n' > "$directory/rootfs.transfer"
    : > "$directory/rootfs.curl.log"
    : > "$directory/signature.headers"
    printf 'effective_url=https://mirror.example/rootfs.tar.gz.sig\nhttp_code=200\nsize_download=566\ncontent_type=application/octet-stream\n' > "$directory/signature.transfer"
    : > "$directory/signature.curl.log"
    printf 'fpr:::::::::68B3537F39A313B3E574D06777193F152BDBE6A6:\n' > "$directory/key.txt"
    printf '%s\n' '-----BEGIN PGP PUBLIC KEY BLOCK-----' 'fixture' '-----END PGP PUBLIC KEY BLOCK-----' > "$directory/signing-key.asc"
    : > "$directory/signature.log"
    : > "$directory/environment.txt"
    printf '[GNUPG:] VALIDSIG 68B3537F39A313B3E574D06777193F152BDBE6A6\n' > "$directory/signature.status"
    printf 'ID=archarm\n' > "$directory/os-release"
    awk 'BEGIN { for (i = 1; i <= 10000; i++) print "usr/lib/morimil-fixture-" i }' > "$directory/archive-list.txt"
    key_sha=$(sha256sum "$directory/signing-key.asc" | awk '{ print $1 }')
    list_sha=$(sha256sum "$directory/archive-list.txt" | awk '{ print $1 }')
    cat > "$directory/release.env" <<EOF
MORIMIL_ARCH_ROOTFS_URL=https://mirror.math.princeton.edu/pub/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz
MORIMIL_ARCH_ROOTFS_SIGNATURE_URL=https://mirror.math.princeton.edu/pub/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6
MORIMIL_ARCH_ROOTFS_SIGNING_KEY_SHA256=$key_sha
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
sed -i 's#https://mirror.math.princeton.edu#http://mirror.math.princeton.edu#' "$HTTP/release.env"
expect_reject 'HTTP evidence URL' "$HTTP"

FINGERPRINT=$TMP_DIR/fingerprint
cp -R "$VALID" "$FINGERPRINT"
sed -i 's/68B3537F39A313B3E574D06777193F152BDBE6A6/0000000000000000000000000000000000000000/' "$FINGERPRINT/release.env"
expect_reject 'incorrect signing fingerprint' "$FINGERPRINT"

KEY_HASH=$TMP_DIR/key-hash
cp -R "$VALID" "$KEY_HASH"
printf 'mutation\n' >> "$KEY_HASH/signing-key.asc"
expect_reject 'mutated signing key export' "$KEY_HASH"

LIST_HASH=$TMP_DIR/list-hash
cp -R "$VALID" "$LIST_HASH"
printf 'mutation\n' >> "$LIST_HASH/archive-list.txt"
expect_reject 'mutated archive list' "$LIST_HASH"

HTTP_STATUS=$TMP_DIR/http-status
cp -R "$VALID" "$HTTP_STATUS"
sed -i 's/http_code=200/http_code=404/' "$HTTP_STATUS/rootfs.transfer"
expect_reject 'failed rootfs transfer' "$HTTP_STATUS"

ARCHIVE=$TMP_DIR/archive
cp -R "$VALID" "$ARCHIVE"
: > "$ARCHIVE/rootfs.tar.gz"
expect_reject 'retained rootfs archive' "$ARCHIVE"

printf 'Arch rootfs release evidence contract tests passed.\n'
