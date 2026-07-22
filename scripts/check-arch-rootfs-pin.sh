#!/bin/sh

set -eu

PIN_FILE=${1:-config/arch-rootfs-release.env}
EXPECTED_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ -f "$PIN_FILE" ] || fail "Arch rootfs pin is missing: $PIN_FILE"

allowed_keys='MORIMIL_ARCH_ROOTFS_URL|MORIMIL_ARCH_ROOTFS_SIGNATURE_URL|MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT|MORIMIL_ARCH_ROOTFS_SIGNING_KEY_SHA256|MORIMIL_ARCH_ROOTFS_SHA256|MORIMIL_ARCH_ROOTFS_SHA512|MORIMIL_ARCH_ROOTFS_SIZE|MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256|MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES|MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256|MORIMIL_ARCH_ROOTFS_SIGNATURE_DATE|MORIMIL_ARCH_ROOTFS_DISCOVERY_RUN|MORIMIL_ARCH_ROOTFS_DISCOVERY_COMMIT|MORIMIL_ARCH_ROOTFS_OBSERVED_AT'

awk -F= -v allowed="$allowed_keys" '
BEGIN {
    split(allowed, names, "|")
    for (i in names) permitted[names[i]] = 1
}
/^[[:space:]]*$/ { next }
/^[[:space:]]*#/ { next }
{
    key = $1
    if (!(key in permitted)) {
        printf "error: unknown Arch rootfs pin key: %s\n", key > "/dev/stderr"
        exit 1
    }
    if (++seen[key] != 1) {
        printf "error: duplicate Arch rootfs pin key: %s\n", key > "/dev/stderr"
        exit 1
    }
}
END {
    if (NR == 0) {
        print "error: Arch rootfs pin is empty" > "/dev/stderr"
        exit 1
    }
    for (key in permitted) {
        if (!(key in seen)) {
            printf "error: missing Arch rootfs pin key: %s\n", key > "/dev/stderr"
            exit 1
        }
    }
}
' "$PIN_FILE" || exit 1

get_value() {
    key=$1
    value=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PIN_FILE")
    [ -n "$value" ] || fail "missing Arch rootfs pin value: $key"
    printf '%s\n' "$value"
}

URL=$(get_value MORIMIL_ARCH_ROOTFS_URL)
SIGNATURE_URL=$(get_value MORIMIL_ARCH_ROOTFS_SIGNATURE_URL)
FINGERPRINT=$(get_value MORIMIL_ARCH_ROOTFS_SIGNING_FINGERPRINT)
SIGNING_KEY_SHA256=$(get_value MORIMIL_ARCH_ROOTFS_SIGNING_KEY_SHA256)
SHA256=$(get_value MORIMIL_ARCH_ROOTFS_SHA256)
SHA512=$(get_value MORIMIL_ARCH_ROOTFS_SHA512)
SIZE=$(get_value MORIMIL_ARCH_ROOTFS_SIZE)
SIGNATURE_SHA256=$(get_value MORIMIL_ARCH_ROOTFS_SIGNATURE_SHA256)
ENTRIES=$(get_value MORIMIL_ARCH_ROOTFS_ARCHIVE_ENTRIES)
LIST_SHA256=$(get_value MORIMIL_ARCH_ROOTFS_ARCHIVE_LIST_SHA256)
SIGNATURE_DATE=$(get_value MORIMIL_ARCH_ROOTFS_SIGNATURE_DATE)
DISCOVERY_RUN=$(get_value MORIMIL_ARCH_ROOTFS_DISCOVERY_RUN)
DISCOVERY_COMMIT=$(get_value MORIMIL_ARCH_ROOTFS_DISCOVERY_COMMIT)
OBSERVED_AT=$(get_value MORIMIL_ARCH_ROOTFS_OBSERVED_AT)

case "$URL" in
    https://*/ArchLinuxARM-aarch64-latest.tar.gz) ;;
    *) fail 'pinned Arch rootfs URL must be HTTPS and select the generic AArch64 tarball' ;;
esac
[ "$SIGNATURE_URL" = "$URL.sig" ] || fail 'pinned signature URL must equal rootfs URL plus .sig'
[ "$FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] || fail 'pinned signing fingerprint does not match the project authority'

validate_hex() {
    name=$1
    value=$2
    length=$3
    case "$value" in *[!0-9a-f]*|'') fail "$name must be lowercase hexadecimal" ;; esac
    [ "${#value}" -eq "$length" ] || fail "$name has an invalid length"
}

validate_hex 'signing key SHA-256' "$SIGNING_KEY_SHA256" 64
validate_hex 'rootfs SHA-256' "$SHA256" 64
validate_hex 'rootfs SHA-512' "$SHA512" 128
validate_hex 'signature SHA-256' "$SIGNATURE_SHA256" 64
validate_hex 'archive list SHA-256' "$LIST_SHA256" 64
validate_hex 'discovery commit' "$DISCOVERY_COMMIT" 40

case "$SIZE" in *[!0-9]*|'') fail 'pinned rootfs size must be numeric' ;; esac
[ "$SIZE" -ge 100000000 ] || fail 'pinned rootfs size is unexpectedly small'
case "$ENTRIES" in *[!0-9]*|'') fail 'pinned archive entry count must be numeric' ;; esac
[ "$ENTRIES" -ge 10000 ] || fail 'pinned archive entry count is unexpectedly small'
case "$DISCOVERY_RUN" in *[!0-9]*|'') fail 'discovery run must be numeric' ;; esac

case "$SIGNATURE_DATE" in ????-??-??) ;; *) fail 'signature date must use YYYY-MM-DD' ;; esac
case "$OBSERVED_AT" in ????-??-??T??:??:??Z) ;; *) fail 'observation timestamp must use UTC ISO-8601' ;; esac

printf 'Arch rootfs pin passed.\n'
printf 'sha256=%s\n' "$SHA256"
printf 'size=%s\n' "$SIZE"
