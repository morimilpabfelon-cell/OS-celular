#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
BOOTSTRAP=$ROOT_DIR/scripts/bootstrap-arch-rootfs.sh
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM
MOCK_BIN=$TMP_DIR/bin
mkdir -p "$MOCK_BIN"

EXPECTED_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

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
        --proto)
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
        printf 'fpr:::::::::68B3537F39A313B3E574D06777193F152BDBE6A6:\n'
        ;;
    *)
        :
        ;;
esac
EOF

cat > "$MOCK_BIN/sha256sum" <<EOF
#!/bin/sh
printf '%s  %s\n' '$EXPECTED_SHA256' "\$1"
EOF

cat > "$MOCK_BIN/bsdtar" <<'EOF'
#!/bin/sh
case " $* " in
    *' -tf '*)
        printf 'etc/os-release\nusr/bin/pacman\n'
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
        mkdir -p "$destination/etc" "$destination/usr/bin"
        printf 'ID=archarm\n' > "$destination/etc/os-release"
        printf '#!/bin/sh\n' > "$destination/usr/bin/pacman"
        chmod 0755 "$destination/usr/bin/pacman"
        ;;
esac
EOF
chmod 0755 "$MOCK_BIN"/*

run_success() {
    destination=$TMP_DIR/machines/morimil-arch
    state_dir=$TMP_DIR/state/arch
    PATH=$MOCK_BIN:$PATH \
        ARCH_ROOTFS_MACHINE_ROOT=$TMP_DIR/machines \
        ARCH_ROOTFS_STATE_ROOT=$TMP_DIR/state \
        ARCH_ROOTFS_EXPECTED_SHA256=$EXPECTED_SHA256 \
        ARCH_ROOTFS_DESTINATION=$destination \
        ARCH_ROOTFS_STATE_DIR=$state_dir \
        sh "$BOOTSTRAP" >/dev/null

    test -x "$destination/usr/bin/pacman"
    grep -Fqx "MORIMIL_ROOTFS_SHA256=$EXPECTED_SHA256" "$destination/etc/morimil/rootfs-source.env"
    grep -Fqx "MORIMIL_ROOTFS_DESTINATION=$destination" "$state_dir/rootfs-source.env"
}

expect_reject() {
    name=$1
    shift
    if PATH=$MOCK_BIN:$PATH "$@" >/dev/null 2>&1; then
        printf 'error: %s was accepted\n' "$name" >&2
        exit 1
    fi
}

run_success

expect_reject 'missing SHA-256' env \
    ARCH_ROOTFS_MACHINE_ROOT="$TMP_DIR/machines" \
    ARCH_ROOTFS_STATE_ROOT="$TMP_DIR/state" \
    ARCH_ROOTFS_DESTINATION="$TMP_DIR/machines/missing-sha" \
    ARCH_ROOTFS_STATE_DIR="$TMP_DIR/state/missing-sha" \
    sh "$BOOTSTRAP"

expect_reject 'HTTP transport' env \
    ARCH_ROOTFS_MACHINE_ROOT="$TMP_DIR/machines" \
    ARCH_ROOTFS_STATE_ROOT="$TMP_DIR/state" \
    ARCH_ROOTFS_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz \
    ARCH_ROOTFS_EXPECTED_SHA256=$EXPECTED_SHA256 \
    ARCH_ROOTFS_DESTINATION="$TMP_DIR/machines/http" \
    ARCH_ROOTFS_STATE_DIR="$TMP_DIR/state/http" \
    sh "$BOOTSTRAP"

expect_reject 'destination outside machine storage' env \
    ARCH_ROOTFS_MACHINE_ROOT="$TMP_DIR/machines" \
    ARCH_ROOTFS_STATE_ROOT="$TMP_DIR/state" \
    ARCH_ROOTFS_EXPECTED_SHA256=$EXPECTED_SHA256 \
    ARCH_ROOTFS_DESTINATION="$TMP_DIR/outside" \
    ARCH_ROOTFS_STATE_DIR="$TMP_DIR/state/outside" \
    sh "$BOOTSTRAP"

expect_reject 'existing destination' env \
    ARCH_ROOTFS_MACHINE_ROOT="$TMP_DIR/machines" \
    ARCH_ROOTFS_STATE_ROOT="$TMP_DIR/state" \
    ARCH_ROOTFS_EXPECTED_SHA256=$EXPECTED_SHA256 \
    ARCH_ROOTFS_DESTINATION="$TMP_DIR/machines/morimil-arch" \
    ARCH_ROOTFS_STATE_DIR="$TMP_DIR/state/existing" \
    sh "$BOOTSTRAP"

printf 'Arch rootfs bootstrap contract tests passed.\n'
