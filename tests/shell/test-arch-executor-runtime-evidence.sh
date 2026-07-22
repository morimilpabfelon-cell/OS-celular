#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
CHECK=$ROOT_DIR/scripts/check-arch-executor-runtime-evidence.sh
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

    cat > "$directory/runtime-summary.env" <<'EOF'
host_architecture=aarch64
clean_boot=yes
clean_shutdown=yes
forced_failure=yes
forced_failure_exit=137
host_survived_failure=yes
reconstruction=yes
rebuild_boot=yes
private_users=yes
private_network=yes
root_read_only=yes
volatile_state=yes
no_new_privileges=yes
EOF

    printf 'MORIMIL_ARCH_EXECUTOR_RUNTIME_VALIDATED=yes\n' > "$directory/validation-status.env"
    printf 'boot_id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\nsentinel_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$directory/host-before.env"
    cp "$directory/host-before.env" "$directory/host-after.env"

    printf 'generation=1\npid1_comm=systemd\nnetwork_interfaces=lo\n' > "$directory/clean-proof.env"
    printf 'generation=2\npid1_comm=systemd\nnetwork_interfaces=lo\n' > "$directory/rebuild-proof.env"
    printf '         0   131072       65536\n' > "$directory/clean-uid-map.txt"
    printf '         0   196608       65536\n' > "$directory/rebuild-uid-map.txt"
    printf '131072\n' > "$directory/generation-1-uid-shift.txt"
    printf '196608\n' > "$directory/generation-2-uid-shift.txt"
    : > "$directory/ownership-shift-generation-1.log"
    : > "$directory/ownership-shift-generation-2.log"
    printf 'ro,nosuid,nodev\n' > "$directory/clean-root-options.txt"
    printf 'ro,nosuid,nodev\n' > "$directory/rebuild-root-options.txt"
    printf 'tmpfs\n' > "$directory/clean-var-fstype.txt"
    printf 'tmpfs\n' > "$directory/rebuild-var-fstype.txt"
    printf 'lo\n' > "$directory/clean-network-interfaces.txt"
    printf 'lo\n' > "$directory/rebuild-network-interfaces.txt"

    printf 'MORIMIL_ROOTFS_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > "$directory/generation-1-rootfs-source.env"
    cp "$directory/generation-1-rootfs-source.env" "$directory/generation-2-rootfs-source.env"
    printf 'rootfs_removed=yes\nstate_removed=yes\nmachine_unregistered=yes\ntrusted_policy_removed=yes\n' > "$directory/cleanup-status.env"
}

VALID=$TMP_DIR/valid
make_evidence "$VALID"
sh "$CHECK" "$VALID" >/dev/null

HOST_ROOT=$TMP_DIR/host-root
cp -R "$VALID" "$HOST_ROOT"
printf '         0        0       65536\n' > "$HOST_ROOT/clean-uid-map.txt"
expect_reject 'host root identity mapping' "$HOST_ROOT"

SHIFT_MISMATCH=$TMP_DIR/shift-mismatch
cp -R "$VALID" "$SHIFT_MISMATCH"
printf '262144\n' > "$SHIFT_MISMATCH/generation-1-uid-shift.txt"
expect_reject 'prepared UID shift mismatch' "$SHIFT_MISMATCH"

UNALIGNED_SHIFT=$TMP_DIR/unaligned-shift
cp -R "$VALID" "$UNALIGNED_SHIFT"
printf '200000\n' > "$UNALIGNED_SHIFT/generation-2-uid-shift.txt"
expect_reject 'unaligned prepared UID shift' "$UNALIGNED_SHIFT"

NETWORK=$TMP_DIR/network
cp -R "$VALID" "$NETWORK"
printf 'eth0\nlo\n' > "$NETWORK/rebuild-network-interfaces.txt"
expect_reject 'non-loopback network interface' "$NETWORK"

WRITABLE=$TMP_DIR/writable
cp -R "$VALID" "$WRITABLE"
printf 'rw,nosuid,nodev\n' > "$WRITABLE/clean-root-options.txt"
expect_reject 'writable root' "$WRITABLE"

PERSISTENT_VAR=$TMP_DIR/persistent-var
cp -R "$VALID" "$PERSISTENT_VAR"
printf 'ext4\n' > "$PERSISTENT_VAR/clean-var-fstype.txt"
expect_reject 'persistent var' "$PERSISTENT_VAR"

HOST_MUTATION=$TMP_DIR/host-mutation
cp -R "$VALID" "$HOST_MUTATION"
sed -i 's/^sentinel_sha256=.*/sentinel_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/' "$HOST_MUTATION/host-after.env"
expect_reject 'host sentinel mutation' "$HOST_MUTATION"

REBUILD_MISMATCH=$TMP_DIR/rebuild-mismatch
cp -R "$VALID" "$REBUILD_MISMATCH"
sed -i 's/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/' "$REBUILD_MISMATCH/generation-2-rootfs-source.env"
expect_reject 'reconstructed rootfs mismatch' "$REBUILD_MISMATCH"

ZERO_FAILURE=$TMP_DIR/zero-failure
cp -R "$VALID" "$ZERO_FAILURE"
sed -i 's/^forced_failure_exit=.*/forced_failure_exit=0/' "$ZERO_FAILURE/runtime-summary.env"
expect_reject 'zero forced-failure exit' "$ZERO_FAILURE"

ARCHIVE=$TMP_DIR/archive
cp -R "$VALID" "$ARCHIVE"
: > "$ARCHIVE/rootfs.tar.gz"
expect_reject 'retained rootfs archive' "$ARCHIVE"

printf 'Arch executor runtime evidence contract tests passed.\n'
