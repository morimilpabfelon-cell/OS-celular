#!/bin/sh

set -eu

EVIDENCE_DIR=${1:-build/arch-rootfs-release}
EXPECTED_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for path in \
    "$EVIDENCE_DIR/release.env" \
    "$EVIDENCE_DIR/rootfs.headers" \
    "$EVIDENCE_DIR/rootfs.transfer" \
    "$EVIDENCE_DIR/rootfs.curl.log" \
    "$EVIDENCE_DIR/signature.headers" \
    "$EVIDENCE_DIR/signature.transfer" \
    "$EVIDENCE_DIR/signature.curl.log" \
    "$EVIDENCE_DIR/key.txt" \
    "$EVIDENCE_DIR/signature.status" \
    "$EVIDENCE_DIR/signature.log" \
    "$EVIDENCE_DIR/archive-list.txt" \
    "$EVIDENCE_DIR/os-release" \
    "$EVIDENCE_DIR/environment.txt"
do
    [ -f "$path" ] || fail "required evidence is missing: $path"
done

if find "$EVIDENCE_DIR" -maxdepth 1 -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.sig' \) | grep -q .; then
    fail 'rootfs archives and detached signatures must not be retained as evidence artifacts'
fi

get_value() {
    key=$1
    value=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$EVIDENCE_DIR/release.env")
    [ -n "$value" ] || fail "missing evidence value: $key"
    printf '%s\n' "$value"
}

URL=$(get_value MORIMIL_ARCH_ROOTFS_URL)
SIGNATURE_URL=$(get_value MORIMIL_ARCH_ROOTFS_SIGNATURE_URL)
FINGERPRINT=$(get_value MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT)
SHA256=$(get_value MORIMIL_ARCH_ROOTFS_SHA256)
SHA512=$(get_value MORIMIL_ARCH_ROOTFS_SHA512)
SIZE=$(get_value MORIMIL_ARCH_ROOTFS_SIZE)
SIGNATURE_SHA256=$(get_value MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256)
ENTRIES=$(get_value MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES)
LIST_SHA256=$(get_value MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256)
VERIFIED=$(get_value MORIMIL_ARCH_ROOTFS_SIGNATURE_VERIFIED)
OBSERVED_AT=$(get_value MORIMIL_ARCH_ROOTFS_OBSERVED_AT)

case "$URL" in https://*) ;; *) fail 'rootfs evidence URL must use HTTPS' ;; esac
[ "$SIGNATURE_URL" = "$URL.sig" ] || fail 'signature URL must be the rootfs URL with .sig appended'
[ "$FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] || fail 'signing fingerprint does not match the project pin'

case "$SHA256" in *[!0-9a-f]*|'') fail 'rootfs SHA-256 must be lowercase hexadecimal' ;; esac
[ "${#SHA256}" -eq 64 ] || fail 'rootfs SHA-256 must contain 64 hexadecimal characters'
case "$SHA512" in *[!0-9a-f]*|'') fail 'rootfs SHA-512 must be lowercase hexadecimal' ;; esac
[ "${#SHA512}" -eq 128 ] || fail 'rootfs SHA-512 must contain 128 hexadecimal characters'
case "$SIGNATURE_SHA256" in *[!0-9a-f]*|'') fail 'signature SHA-256 must be lowercase hexadecimal' ;; esac
[ "${#SIGNATURE_SHA256}" -eq 64 ] || fail 'signature SHA-256 must contain 64 hexadecimal characters'
case "$LIST_SHA256" in *[!0-9a-f]*|'') fail 'archive list SHA-256 must be lowercase hexadecimal' ;; esac
[ "${#LIST_SHA256}" -eq 64 ] || fail 'archive list SHA-256 must contain 64 hexadecimal characters'

case "$SIZE" in *[!0-9]*|'') fail 'rootfs size must be a positive integer' ;; esac
[ "$SIZE" -ge 100000000 ] || fail 'rootfs size is unexpectedly small'
case "$ENTRIES" in *[!0-9]*|'') fail 'archive entry count must be a positive integer' ;; esac
[ "$ENTRIES" -ge 10000 ] || fail 'archive entry count is unexpectedly small'
[ "$VERIFIED" = yes ] || fail 'signature verification status must be yes'

case "$OBSERVED_AT" in
    ????-??-??T??:??:??Z) ;;
    *) fail 'observation timestamp must use UTC ISO-8601 format' ;;
esac

grep -Fq 'http_code=200' "$EVIDENCE_DIR/rootfs.transfer" || fail 'rootfs transfer did not finish with HTTP 200'
grep -Fq 'http_code=200' "$EVIDENCE_DIR/signature.transfer" || fail 'signature transfer did not finish with HTTP 200'
grep -Fq '[GNUPG:] VALIDSIG ' "$EVIDENCE_DIR/signature.status" || fail 'signature status lacks VALIDSIG'
grep -Eq '^ID=archarm$|^ID=arch$' "$EVIDENCE_DIR/os-release" || fail 'os-release does not identify Arch Linux ARM'

ACTUAL_LIST_SHA256=$(sha256sum "$EVIDENCE_DIR/archive-list.txt" | awk '{ print $1 }')
[ "$ACTUAL_LIST_SHA256" = "$LIST_SHA256" ] || fail 'archive list checksum does not match release metadata'

printf 'Arch rootfs release evidence passed.\n'
printf 'sha256=%s\n' "$SHA256"
printf 'size=%s\n' "$SIZE"
