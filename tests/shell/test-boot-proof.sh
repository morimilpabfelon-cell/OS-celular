#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

REPOSITORY_ROOT=$SCRIPT_DIR/../..
BUILD_SCRIPT=$REPOSITORY_ROOT/scripts/build-qemu-arm64.sh
CONFIGURE_SCRIPT=$REPOSITORY_ROOT/scripts/configure-validation-image.sh
VERIFY_SCRIPT=$REPOSITORY_ROOT/scripts/verify-boot-log.sh
TEST_TMP=$(mktemp -d /tmp/morimil-boot-proof-tests.XXXXXX)
MOCK_BIN=$TEST_TMP/bin
MOCK_LOG=$TEST_TMP/mmdebstrap.log
TEST_BUILD=$TEST_TMP/build

trap 'rm -rf "$TEST_TMP"' 0
mkdir -p "$MOCK_BIN" "$TEST_BUILD"

printf 'contract: validation image customization\n'
IMAGE_ROOT=$TEST_TMP/image-root
MORIMIL_IMAGE_ROOT=$IMAGE_ROOT sh "$CONFIGURE_SCRIPT"

test -x "$IMAGE_ROOT/usr/local/sbin/morimil-boot-proof"
test -f "$IMAGE_ROOT/etc/systemd/system/morimil-boot-proof.service"
test -f "$IMAGE_ROOT/etc/systemd/system/morimil-boot-proof.timer"
test -L "$IMAGE_ROOT/etc/systemd/system/multi-user.target.wants/morimil-boot-proof.timer"
grep -Fqx -- 'morimil-validation' "$IMAGE_ROOT/etc/hostname"
grep -Fq -- 'OnActiveSec=5s' "$IMAGE_ROOT/etc/systemd/system/morimil-boot-proof.timer"
grep -Fq -- 'MORIMIL_BOOT_PROOF target=multi-user.target state=active' "$IMAGE_ROOT/usr/local/sbin/morimil-boot-proof"

cat > "$MOCK_BIN/mmdebstrap-autopkgtest-build-qemu" <<'MOCK'
#!/bin/sh
set -eu

: "${MORIMIL_MOCK_LOG:?}"
output=
for argument in "$@"; do
    printf '%s\n' "$argument" >> "$MORIMIL_MOCK_LOG"
    output=$argument
done
printf 'mock-image\n' > "$output"
MOCK
chmod 0755 "$MOCK_BIN/mmdebstrap-autopkgtest-build-qemu"

printf 'contract: builder passes customization and fingerprints it\n'
env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_LOG="$MOCK_LOG" \
    DEBIAN_SNAPSHOT=20260718T000000Z \
    SOURCE_DATE_EPOCH=1784332800 \
    IMAGE_SIZE=64M \
    OUTPUT_IMAGE="$TEST_BUILD/morimil-proof.raw" \
    CUSTOMIZE_SCRIPT="$CONFIGURE_SCRIPT" \
    sh "$BUILD_SCRIPT" > "$TEST_TMP/build.out"

grep -Fq -- '--script=' "$MOCK_LOG"
grep -Fqx -- 'format_version=2' "$TEST_BUILD/morimil-proof.raw.metadata"
grep -Fqx -- 'snapshot_requested=20260718T000000Z' "$TEST_BUILD/morimil-proof.raw.metadata"
grep -Fq -- 'customize_script_sha256=' "$TEST_BUILD/morimil-proof.raw.metadata"

printf 'contract: boot log verifier accepts proof marker\n'
printf '%s\n' \
    'UEFI started' \
    'MORIMIL_BOOT_PROOF target=multi-user.target state=active' \
    'Power down' > "$TEST_TMP/boot-success.log"
sh "$VERIFY_SCRIPT" "$TEST_TMP/boot-success.log" > "$TEST_TMP/verify-success.out"

printf 'contract: boot log verifier rejects missing proof\n'
printf '%s\n' 'UEFI started' 'login:' > "$TEST_TMP/boot-missing.log"
if sh "$VERIFY_SCRIPT" "$TEST_TMP/boot-missing.log" > "$TEST_TMP/verify-missing.out" 2>&1; then
    printf 'error: boot verifier accepted a log without the proof marker\n' >&2
    exit 1
fi
grep -Fq -- 'boot proof marker was not found' "$TEST_TMP/verify-missing.out"

printf 'contract: boot log verifier rejects guest failure\n'
printf '%s\n' 'MORIMIL_BOOT_PROOF_FAILED target=multi-user.target state=inactive' > "$TEST_TMP/boot-failed.log"
if sh "$VERIFY_SCRIPT" "$TEST_TMP/boot-failed.log" > "$TEST_TMP/verify-failed.out" 2>&1; then
    printf 'error: boot verifier accepted a guest failure marker\n' >&2
    exit 1
fi
grep -Fq -- 'guest reported that multi-user.target was not active' "$TEST_TMP/verify-failed.out"

printf 'Boot proof contract tests passed.\n'
printf 'These tests use mocks and do not prove a real boot.\n'
