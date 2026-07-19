#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

REPOSITORY_ROOT=$SCRIPT_DIR/../..
BUILD_SCRIPT=$REPOSITORY_ROOT/scripts/build-qemu-arm64.sh
RUN_SCRIPT=$REPOSITORY_ROOT/scripts/run-qemu-arm64.sh
TEST_TMP=$(mktemp -d /tmp/morimil-contract-tests.XXXXXX)
MOCK_BIN=$TEST_TMP/bin
TEST_BUILD=$TEST_TMP/build
BUILD_LOG=$TEST_TMP/build.log
QEMU_LOG=$TEST_TMP/qemu.log

trap 'rm -rf "$TEST_TMP"' 0
mkdir -p "$MOCK_BIN" "$TEST_BUILD"

cat > "$MOCK_BIN/mmdebstrap-autopkgtest-build-qemu" <<'MOCK_BUILD'
#!/bin/sh
set -eu

: "${MORIMIL_MOCK_BUILD_LOG:?}"
: "${MORIMIL_MOCK_TEMP_MODE_LOG:?}"

output=
for argument in "$@"; do
    printf '%s\n' "$argument" >> "$MORIMIL_MOCK_BUILD_LOG"
    output=$argument
done

if [ -z "$output" ]; then
    printf 'mock builder did not receive an output path\n' >&2
    exit 90
fi

output_directory=${output%/*}
if [ "$output_directory" = "$output" ]; then
    output_directory=.
fi

stat -c '%a' "$output_directory" > "$MORIMIL_MOCK_TEMP_MODE_LOG"
printf 'morimil-contract-image\n' > "$output"
MOCK_BUILD

cat > "$MOCK_BIN/qemu-system-aarch64" <<'MOCK_QEMU'
#!/bin/sh
set -eu

: "${MORIMIL_MOCK_QEMU_LOG:?}"
printf '%s\n' "$@" > "$MORIMIL_MOCK_QEMU_LOG"
MOCK_QEMU

chmod 0755 \
    "$MOCK_BIN/mmdebstrap-autopkgtest-build-qemu" \
    "$MOCK_BIN/qemu-system-aarch64"

printf 'contract: build success path\n'
env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_BUILD_LOG="$BUILD_LOG" \
    MORIMIL_MOCK_TEMP_MODE_LOG="$TEST_TMP/temp-mode.log" \
    DEBIAN_SNAPSHOT=20260719T000000Z \
    SOURCE_DATE_EPOCH=1784419200 \
    IMAGE_SIZE=64M \
    OUTPUT_IMAGE="$TEST_BUILD/morimil-test.raw" \
    sh "$BUILD_SCRIPT" > "$TEST_TMP/build-success.out"

if [ ! -f "$TEST_BUILD/morimil-test.raw" ]; then
    printf 'error: builder did not create the expected image\n' >&2
    exit 1
fi

if [ ! -f "$TEST_BUILD/morimil-test.raw.sha256" ]; then
    printf 'error: builder did not create the checksum manifest\n' >&2
    exit 1
fi

if [ ! -f "$TEST_BUILD/morimil-test.raw.metadata" ]; then
    printf 'error: builder did not create metadata\n' >&2
    exit 1
fi

(
    cd "$TEST_BUILD" || exit 1
    sha256sum -c morimil-test.raw.sha256
) > "$TEST_TMP/checksum.out"

grep -Fqx -- '--boot=efi' "$BUILD_LOG"
grep -Fqx -- '--arch=arm64' "$BUILD_LOG"
grep -Fqx -- '--size=64M' "$BUILD_LOG"
grep -Fqx -- '--mirror=https://snapshot.debian.org/archive/debian/20260719T000000Z/' "$BUILD_LOG"
grep -Fqx -- '755' "$TEST_TMP/temp-mode.log"
grep -Fqx -- 'snapshot_requested=20260719T000000Z' "$TEST_BUILD/morimil-test.raw.metadata"
grep -Fqx -- 'source_date_epoch=1784419200' "$TEST_BUILD/morimil-test.raw.metadata"

printf 'contract: builder refuses overwrite\n'
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_BUILD_LOG="$TEST_TMP/overwrite-build.log" \
    MORIMIL_MOCK_TEMP_MODE_LOG="$TEST_TMP/overwrite-mode.log" \
    DEBIAN_SNAPSHOT=20260719T000000Z \
    SOURCE_DATE_EPOCH=1784419200 \
    OUTPUT_IMAGE="$TEST_BUILD/morimil-test.raw" \
    sh "$BUILD_SCRIPT" > "$TEST_TMP/overwrite.out" 2>&1
then
    printf 'error: builder replaced an existing artifact without FORCE=1\n' >&2
    exit 1
fi

grep -Fq -- 'output already exists' "$TEST_TMP/overwrite.out"

printf 'contract: builder rejects malformed snapshot\n'
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_BUILD_LOG="$TEST_TMP/invalid-build.log" \
    MORIMIL_MOCK_TEMP_MODE_LOG="$TEST_TMP/invalid-mode.log" \
    DEBIAN_SNAPSHOT=latest \
    SOURCE_DATE_EPOCH=1784419200 \
    OUTPUT_IMAGE="$TEST_BUILD/invalid.raw" \
    sh "$BUILD_SCRIPT" > "$TEST_TMP/invalid-snapshot.out" 2>&1
then
    printf 'error: builder accepted a malformed snapshot timestamp\n' >&2
    exit 1
fi

grep -Fq -- 'exact format YYYYMMDDThhmmssZ' "$TEST_TMP/invalid-snapshot.out"

printf 'contract: QEMU invocation is isolated and deterministic\n'
printf 'firmware-code\n' > "$TEST_TMP/AAVMF_CODE.fd"
printf 'firmware-vars\n' > "$TEST_TMP/AAVMF_VARS.fd"

env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_QEMU_LOG="$QEMU_LOG" \
    IMAGE="$TEST_BUILD/morimil-test.raw" \
    FIRMWARE_CODE="$TEST_TMP/AAVMF_CODE.fd" \
    FIRMWARE_VARS_TEMPLATE="$TEST_TMP/AAVMF_VARS.fd" \
    FIRMWARE_VARS="$TEST_BUILD/runtime-vars.fd" \
    MEMORY_MIB=1024 \
    CPUS=1 \
    sh "$RUN_SCRIPT" > "$TEST_TMP/qemu-success.out"

grep -Fqx -- 'virt,accel=tcg' "$QEMU_LOG"
grep -Fqx -- 'cortex-a57' "$QEMU_LOG"
grep -Fqx -- '-snapshot' "$QEMU_LOG"
grep -Fqx -- '-nic' "$QEMU_LOG"
grep -Fqx -- 'none' "$QEMU_LOG"
cmp -s "$TEST_TMP/AAVMF_VARS.fd" "$TEST_BUILD/runtime-vars.fd"

printf 'contract: QEMU runner requires checksum\n'
cp "$TEST_BUILD/morimil-test.raw" "$TEST_BUILD/unverified.raw"
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_QEMU_LOG="$TEST_TMP/unverified-qemu.log" \
    IMAGE="$TEST_BUILD/unverified.raw" \
    FIRMWARE_CODE="$TEST_TMP/AAVMF_CODE.fd" \
    FIRMWARE_VARS_TEMPLATE="$TEST_TMP/AAVMF_VARS.fd" \
    FIRMWARE_VARS="$TEST_BUILD/unverified-vars.fd" \
    sh "$RUN_SCRIPT" > "$TEST_TMP/unverified.out" 2>&1
then
    printf 'error: QEMU runner accepted an image without a checksum\n' >&2
    exit 1
fi

grep -Fq -- 'checksum manifest not found' "$TEST_TMP/unverified.out"

printf 'contract: QEMU runner rejects invalid resources\n'
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_QEMU_LOG="$TEST_TMP/resources-qemu.log" \
    IMAGE="$TEST_BUILD/morimil-test.raw" \
    FIRMWARE_CODE="$TEST_TMP/AAVMF_CODE.fd" \
    FIRMWARE_VARS_TEMPLATE="$TEST_TMP/AAVMF_VARS.fd" \
    FIRMWARE_VARS="$TEST_BUILD/resources-vars.fd" \
    MEMORY_MIB=0 \
    sh "$RUN_SCRIPT" > "$TEST_TMP/invalid-resources.out" 2>&1
then
    printf 'error: QEMU runner accepted zero memory\n' >&2
    exit 1
fi

grep -Fq -- 'MEMORY_MIB must be a positive integer' "$TEST_TMP/invalid-resources.out"

printf 'contract: QEMU runner protects firmware template\n'
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_QEMU_LOG="$TEST_TMP/firmware-qemu.log" \
    IMAGE="$TEST_BUILD/morimil-test.raw" \
    FIRMWARE_CODE="$TEST_TMP/AAVMF_CODE.fd" \
    FIRMWARE_VARS_TEMPLATE="$TEST_TMP/AAVMF_VARS.fd" \
    FIRMWARE_VARS="$TEST_TMP/AAVMF_VARS.fd" \
    sh "$RUN_SCRIPT" > "$TEST_TMP/firmware-template.out" 2>&1
then
    printf 'error: QEMU runner allowed overwriting the firmware template\n' >&2
    exit 1
fi

grep -Fq -- 'must not overwrite the firmware template' "$TEST_TMP/firmware-template.out"

printf 'All shell contract tests passed.\n'
printf 'These tests use mocks and do not prove image construction or boot.\n'
