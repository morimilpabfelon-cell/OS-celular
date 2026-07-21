#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

REPOSITORY_ROOT=$SCRIPT_DIR/../..
INSPECT_SCRIPT=$REPOSITORY_ROOT/scripts/inspect-ext4-root.sh
MANIFEST_SCRIPT=$REPOSITORY_ROOT/scripts/manifest-ext4-tree.py
TEST_TMP=$(mktemp -d /tmp/morimil-ext4-inspection-tests.XXXXXX)
MOCK_BIN=$TEST_TMP/bin
MOCK_LOG=$TEST_TMP/mock.log
IMAGE=$TEST_TMP/morimil.raw
OUTPUT_DIR=$TEST_TMP/output

trap 'rm -rf "$TEST_TMP"' 0
mkdir -p "$MOCK_BIN"
dd if=/dev/zero of="$IMAGE" bs=512 count=32 status=none

cat > "$MOCK_BIN/id" <<'MOCK_ID'
#!/bin/sh
set -eu
if [ "${1:-}" = -u ]; then
    printf '0\n'
else
    /usr/bin/id "$@"
fi
MOCK_ID

cat > "$MOCK_BIN/sfdisk" <<'MOCK_SFDISK'
#!/bin/sh
set -eu
case "$1" in
    --dump)
        cat <<EOF_DUMP
label: gpt
label-id: 11111111-1111-5111-8111-111111111111
device: $2
unit: sectors
first-lba: 1
last-lba: 31
sector-size: 512

${2}1 : start=2, size=6, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
${2}2 : start=8, size=16, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF_DUMP
        ;;
    --part-type) printf '%s\n' '0FC63DAF-8483-4772-8E79-3D69D8477DE4' ;;
    *) exit 91 ;;
esac
MOCK_SFDISK

cat > "$MOCK_BIN/losetup" <<'MOCK_LOSETUP'
#!/bin/sh
set -eu
: "${MORIMIL_MOCK_LOG:?}"
printf 'losetup %s\n' "$*" >> "$MORIMIL_MOCK_LOG"
case "$1" in
    --find) printf '%s\n' '/dev/loop-morimil-test' ;;
    --list) printf '1\n' ;;
    --detach) ;;
    *) exit 92 ;;
esac
MOCK_LOSETUP

cat > "$MOCK_BIN/dumpe2fs" <<'MOCK_DUMPE2FS'
#!/bin/sh
set -eu
case "$1" in
    -h) printf 'Filesystem UUID: mock-root\nFilesystem created: fixed\n' ;;
    -g) printf 'group:block:super:gdt:bbitmap:ibitmap:itable\n' ;;
    *) exit 93 ;;
esac
MOCK_DUMPE2FS

cat > "$MOCK_BIN/mount" <<'MOCK_MOUNT'
#!/bin/sh
set -eu
: "${MORIMIL_MOCK_LOG:?}"
printf 'mount %s\n' "$*" >> "$MORIMIL_MOCK_LOG"
for argument in "$@"; do
    target=$argument
done
mkdir -p "$target/etc"
printf 'morimil\n' > "$target/etc/config"
ln -s etc/config "$target/config-link"
if [ -n "${MORIMIL_MOCK_MUTATE_IMAGE:-}" ]; then
    printf 'x' >> "$MORIMIL_MOCK_MUTATE_IMAGE"
fi
MOCK_MOUNT

cat > "$MOCK_BIN/umount" <<'MOCK_UMOUNT'
#!/bin/sh
set -eu
: "${MORIMIL_MOCK_LOG:?}"
printf 'umount %s\n' "$*" >> "$MORIMIL_MOCK_LOG"
MOCK_UMOUNT

chmod 0755 "$MOCK_BIN"/*

printf 'contract: read-only ext4 inspection\n'
env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_LOG="$MOCK_LOG" \
    MANIFEST_SCRIPT="$MANIFEST_SCRIPT" \
    sh "$INSPECT_SCRIPT" "$IMAGE" "$OUTPUT_DIR" \
    > "$TEST_TMP/inspection.out"

for required_output in \
    ext4-superblock.txt \
    ext4-groups.txt \
    ext4-tree.jsonl \
    ext4-tree.sha256 \
    ext4-inspection-status.txt
do
    test -s "$OUTPUT_DIR/$required_output"
done

grep -Fq -- '--read-only' "$MOCK_LOG"
grep -Fq -- '--offset 4096' "$MOCK_LOG"
grep -Fq -- '--sizelimit 8192' "$MOCK_LOG"
grep -Fq -- '-o ro,noload,nodev,nosuid,noexec' "$MOCK_LOG"
grep -Fqx -- 'loop_read_only=1' "$OUTPUT_DIR/ext4-inspection-status.txt"
grep -Fqx -- 'root_start_sector=8' "$OUTPUT_DIR/ext4-inspection-status.txt"
grep -Fqx -- 'root_sector_count=16' "$OUTPUT_DIR/ext4-inspection-status.txt"
grep -Fq -- '"path":"etc/config"' "$OUTPUT_DIR/ext4-tree.jsonl"
(
    cd "$OUTPUT_DIR" || exit 1
    sha256sum -c ext4-tree.sha256
) > "$TEST_TMP/tree-checksum.out"

printf 'contract: inspection detects image mutation\n'
MUTATED_IMAGE=$TEST_TMP/mutated.raw
MUTATED_OUTPUT=$TEST_TMP/mutated-output
cp "$IMAGE" "$MUTATED_IMAGE"
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_LOG="$TEST_TMP/mutated.log" \
    MORIMIL_MOCK_MUTATE_IMAGE="$MUTATED_IMAGE" \
    MANIFEST_SCRIPT="$MANIFEST_SCRIPT" \
    sh "$INSPECT_SCRIPT" "$MUTATED_IMAGE" "$MUTATED_OUTPUT" \
    > "$TEST_TMP/mutated.out" 2>&1
then
    printf 'error: inspection accepted a mutated image\n' >&2
    exit 1
fi
grep -Fq -- 'image changed during read-only ext4 inspection' "$TEST_TMP/mutated.out"
grep -Fq -- 'losetup --detach /dev/loop-morimil-test' "$TEST_TMP/mutated.log"

printf 'Ext4 inspection contract tests passed.\n'
printf 'These tests use mocks and do not inspect a real ext4 image.\n'
