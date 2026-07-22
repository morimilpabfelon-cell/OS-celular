#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
CHECK=$ROOT_DIR/scripts/check-arch-rootfs-pin.sh
VALID=$ROOT_DIR/config/arch-rootfs-release.env
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

expect_reject() {
    name=$1
    file=$2
    if sh "$CHECK" "$file" >/dev/null 2>&1; then
        fail "$name was accepted"
    fi
}

sh "$CHECK" "$VALID" >/dev/null

HTTP=$TMP_DIR/http.env
sed 's#^MORIMIL_ARCH_ROOTFS_URL=https:#MORIMIL_ARCH_ROOTFS_URL=http:#' "$VALID" > "$HTTP"
expect_reject 'HTTP rootfs pin' "$HTTP"

FINGERPRINT=$TMP_DIR/fingerprint.env
sed 's/^MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT=.*/MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT=0000000000000000000000000000000000000000/' "$VALID" > "$FINGERPRINT"
expect_reject 'incorrect authority fingerprint' "$FINGERPRINT"

KEY_SHA=$TMP_DIR/key-sha.env
sed 's/^MORIMIL_ARCH_ROOTFS_SIGNING_KEY_SHA256=.*/MORIMIL_ARCH_ROOTFS_SIGNING_KEY_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaag/' "$VALID" > "$KEY_SHA"
expect_reject 'non-hexadecimal signing key SHA-256' "$KEY_SHA"

SHA=$TMP_DIR/sha.env
sed 's/^MORIMIL_ARCH_ROOTFS_SHA256=.*/MORIMIL_ARCH_ROOTFS_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaag/' "$VALID" > "$SHA"
expect_reject 'non-hexadecimal rootfs SHA-256' "$SHA"

UNKNOWN=$TMP_DIR/unknown.env
{
    cat "$VALID"
    printf 'MORIMIL_ARCH_ROOTFS_UNAPPROVED=yes\n'
} > "$UNKNOWN"
expect_reject 'unknown pin key' "$UNKNOWN"

DUPLICATE=$TMP_DIR/duplicate.env
{
    cat "$VALID"
    printf 'MORIMIL_ARCH_ROOTFS_SIZE=818293654\n'
} > "$DUPLICATE"
expect_reject 'duplicate pin key' "$DUPLICATE"

MISSING_KEY=$TMP_DIR/missing-key.env
grep -v '^MORIMIL_ARCH_ROOTFS_SIGNING_KEY_SHA256=' "$VALID" > "$MISSING_KEY"
expect_reject 'missing signing key checksum' "$MISSING_KEY"

MISSING_SIGNATURE=$TMP_DIR/missing-signature.env
grep -v '^MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256=' "$VALID" > "$MISSING_SIGNATURE"
expect_reject 'missing signature checksum' "$MISSING_SIGNATURE"

printf 'Arch rootfs pin contract tests passed.\n'
