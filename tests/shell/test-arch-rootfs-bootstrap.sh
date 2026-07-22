#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
BOOTSTRAP=$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh
PIN_FILE=$ROOT_DIR/config/arch-rootfs-release.env
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM
MOCK_BIN=$TMP_DIR/bin
mkdir -p "$MOCK_BIN"

EXPECTED_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EXPECTED_SHA512=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EXPECTED_SIGNATURE_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
EXPECTED_ARCHIVE_LIST_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EXPECTED_SIZE=8
EXPECTED_ENTRIES=2

cat > "$MOCK_BIN/id" <<'EOF'
#!/bin/sh
printf '0\n'
EOF

cat > "$MOCK_BIN/curl" <<'EOF'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            output=$2
            shift 2
            ;;
        --fail|--location|--tlsv1.2)
            shift
            ;;
        --proto|--proto-redir)
            shift 2
            ;;
        *)
            url=$1
            shift
            ;;
    esac
done
[ -n "$output" ] || exit 2
case "$url" in
    *.sig) printf 'signature\n' > "$output" ;;
    *) printf 'archive\n' > "$output" ;;
esac
EOF

cat > "$MOCK_BIN/gpg" <<'EOF'
#!/bin/sh
case " $* " in
    *' --with-colons --fingerprint '*)
        fingerprint=${MOCK_GPG_FINGERPRINT:-68B3537F39A313B3E574D06777193F152BDBE6A6}
        printf 'fpr:::::::::%s:\n' "$fingerprint"
        ;;
    *' --verify '*)
        [ "${MOCK_GPG_VERIFY_FAIL:-0}" -eq 0 ]
        ;;
    *)
        :
        ;;
esac
EOF

cat > "$MOCK_BIN/sha256sum" <<'EOF'
#!/bin/sh
case "$1" in
    *.sig) digest=${MOCK_SIGNATURE_SHA256:-cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc} ;;
    *archive-list.txt) digest=${MOCK_ARCHIVE_LIST_SHA256:-dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd} ;;
    *) digest=${MOCK_SHA256:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa} ;;
esac
printf '%s  %s\n' "$digest" "$1"
EOF

cat > "$MOCK_BIN/sha512sum" <<'EOF'
#!/bin/sh
digest=${MOCK_SHA512:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}
printf '%s  %s\n' "$digest" "$1"
EOF

cat > "$MOCK_BIN/bsdtar" <<'EOF'
#!/bin/sh
case " $* " in
    *' -tf '*)
        printf 'usr/lib/os-release\nusr/bin/pacman\n'
        ;;
    *)
        destination=
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -C ]; then
                destination=$2
                break
            fi
            shift
        done
        [ -n "$destination" ] || exit 2
        mkdir -p "$destination/usr/lib" "$destination/usr/bin"
        printf 'ID=archarm\n' > "$destination/usr/lib/os-release"
        mkdir -p "$destination/etc"
        ln -s ../usr/lib/os-release "$destination/etc/os-release"
        printf '#!/bin/sh\n' > "$destination/usr/bin/pacman"
        chmod 0755 "$destination/usr/bin/pacman"
        ;;
esac
EOF
chmod 0755 "$MOCK_BIN"/*

common_env() {
    destination=$1
    state_dir=$2
    printf '%s\n' \
        "ARCH_ROOTFS_PIN_FILE=$PIN_FILE" \
        "ARCH_ROOTFS_MACHINE_ROOT=$TMP_DIR/machines" \
        "ARCH_ROOTFS_STATE_ROOT=$TMP_DIR/state" \
        "ARCH_ROOTFS_EXPECTED_SHA256=$EXPECTED_SHA256" \
        "ARCH_ROOTFS_EXPECTED_SHA512=$EXPECTED_SHA512" \
        "ARCH_ROOTFS_EXPECTED_SIZE=$EXPECTED_SIZE" \
        "ARCH_ROOTFS_EXPECTED_SIGNATURE_SHA256=$EXPECTED_SIGNATURE_SHA256" \
        "ARCH_ROOTFS_EXPECTED_ARCHIVE_ENTRIES=$EXPECTED_ENTRIES" \
        "ARCH_ROOTFS_EXPECTED_ARCHIVE_LIST_SHA256=$EXPECTED_ARCHIVE_LIST_SHA256" \
        "ARCH_ROOTFS_DESTINATION=$destination" \
        "ARCH_ROOTFS_STATE_DIR=$state_dir"
}

run_bootstrap() {
    destination=$1
    state_dir=$2
    shift 2
    common_file=$TMP_DIR/common.$$
    extra_file=$TMP_DIR/extra.$$
    common_env "$destination" "$state_dir" > "$common_file"
    : > "$extra_file"
    for assignment in "$@"; do
        printf '%s\n' "$assignment" >> "$extra_file"
    done
    set --
    while IFS= read -r assignment; do
        set -- "$@" "$assignment"
    done < "$common_file"
    while IFS= read -r assignment; do
        set -- "$@" "$assignment"
    done < "$extra_file"
    rm -f "$common_file" "$extra_file"
    PATH=$MOCK_BIN:$PATH env "$@" sh "$BOOTSTRAP"
}

run_success() {
    destination=$TMP_DIR/machines/morimil-arch
    state_dir=$TMP_DIR/state/arch
    run_bootstrap "$destination" "$state_dir" >/dev/null

    test -x "$destination/usr/bin/pacman"
    grep -Fqx "MORIMIL_ROOTFS_SHA256=$EXPECTED_SHA256" "$destination/etc/morimil/rootfs-source.env"
    grep -Fqx "MORIMIL_ROOTFS_SHA512=$EXPECTED_SHA512" "$state_dir/rootfs-source.env"
    grep -Fqx "MORIMIL_ROOTFS_DESTINATION=$destination" "$state_dir/rootfs-source.env"
}

expect_reject_without_publish() {
    name=$1
    destination=$2
    state_dir=$3
    shift 3
    if run_bootstrap "$destination" "$state_dir" "$@" >/dev/null 2>&1; then
        printf 'error: %s was accepted\n' "$name" >&2
        exit 1
    fi
    if [ -e "$destination" ]; then
        printf 'error: %s published a destination after failure\n' "$name" >&2
        exit 1
    fi
    if [ -e "$state_dir/rootfs-source.env" ]; then
        printf 'error: %s published state metadata after failure\n' "$name" >&2
        exit 1
    fi
}

run_success

INVALID_PIN=$TMP_DIR/invalid-pin.env
grep -v '^MORIMIL_ARCH_ROOTFS_SHA256=' "$PIN_FILE" > "$INVALID_PIN"
expect_reject_without_publish 'invalid pin' "$TMP_DIR/machines/invalid-pin" "$TMP_DIR/state/invalid-pin" \
    "ARCH_ROOTFS_PIN_FILE=$INVALID_PIN"

expect_reject_without_publish 'HTTP transport' "$TMP_DIR/machines/http" "$TMP_DIR/state/http" \
    'ARCH_ROOTFS_URL=http://example.invalid/rootfs.tar.gz'

expect_reject_without_publish 'destination outside machine storage' "$TMP_DIR/outside" "$TMP_DIR/state/outside" \
    "ARCH_ROOTFS_DESTINATION=$TMP_DIR/outside"

expect_reject_without_publish 'wrong signing fingerprint' "$TMP_DIR/machines/fingerprint" "$TMP_DIR/state/fingerprint" \
    'MOCK_GPG_FINGERPRINT=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'

expect_reject_without_publish 'signature verification failure' "$TMP_DIR/machines/signature" "$TMP_DIR/state/signature" \
    'MOCK_GPG_VERIFY_FAIL=1'

expect_reject_without_publish 'signature SHA-256 mismatch' "$TMP_DIR/machines/signature-sha" "$TMP_DIR/state/signature-sha" \
    'MOCK_SIGNATURE_SHA256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

expect_reject_without_publish 'rootfs SHA-256 mismatch' "$TMP_DIR/machines/sha256" "$TMP_DIR/state/sha256" \
    'MOCK_SHA256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

expect_reject_without_publish 'rootfs SHA-512 mismatch' "$TMP_DIR/machines/sha512" "$TMP_DIR/state/sha512" \
    'MOCK_SHA512=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

expect_reject_without_publish 'rootfs size mismatch' "$TMP_DIR/machines/size" "$TMP_DIR/state/size" \
    'ARCH_ROOTFS_EXPECTED_SIZE=9'

expect_reject_without_publish 'archive entry mismatch' "$TMP_DIR/machines/entries" "$TMP_DIR/state/entries" \
    'ARCH_ROOTFS_EXPECTED_ARCHIVE_ENTRIES=3'

expect_reject_without_publish 'archive-list SHA-256 mismatch' "$TMP_DIR/machines/list-sha" "$TMP_DIR/state/list-sha" \
    'MOCK_ARCHIVE_LIST_SHA256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

if run_bootstrap "$TMP_DIR/machines/morimil-arch" "$TMP_DIR/state/existing" >/dev/null 2>&1; then
    printf 'error: existing destination was accepted\n' >&2
    exit 1
fi

printf 'Arch rootfs bootstrap contract tests passed.\n'
