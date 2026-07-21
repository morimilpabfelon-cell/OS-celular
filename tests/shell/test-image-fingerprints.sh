#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

REPOSITORY_ROOT=$SCRIPT_DIR/../..
FINGERPRINT_SCRIPT=$REPOSITORY_ROOT/scripts/fingerprint-qemu-image.sh
TEST_TMP=$(mktemp -d /tmp/morimil-fingerprint-tests.XXXXXX)
MOCK_BIN=$TEST_TMP/bin
IMAGE=$TEST_TMP/morimil.raw

trap 'rm -rf "$TEST_TMP"' 0
mkdir -p "$MOCK_BIN"

dd if=/dev/zero of="$IMAGE" bs=512 count=20 status=none
printf 'MORIMIL-MBR' | dd of="$IMAGE" bs=1 seek=32 conv=notrunc status=none
printf 'EFI-CONTENT' | dd of="$IMAGE" bs=1 seek=$((2 * 512 + 16)) conv=notrunc status=none
printf 'ROOT-CONTENT' | dd of="$IMAGE" bs=1 seek=$((8 * 512 + 16)) conv=notrunc status=none

cat > "$MOCK_BIN/sfdisk" <<'MOCK_SFDISK'
#!/bin/sh
set -eu

case "$1" in
    --dump)
        if [ "${MORIMIL_MOCK_OVERLAP:-0}" = 1 ]; then
            root_start=5
        else
            root_start=8
        fi
        cat <<EOF_DUMP
label: gpt
label-id: 11111111-1111-5111-8111-111111111111
device: $2
unit: sectors
first-lba: 1
last-lba: 19
sector-size: 512

${2}1 : start=2, size=4, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=22222222-2222-5222-8222-222222222222
${2}2 : start=$root_start, size=8, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=33333333-3333-5333-8333-333333333333
EOF_DUMP
        ;;
    --disk-id) printf '%s\n' '11111111-1111-5111-8111-111111111111' ;;
    --part-type)
        case "$3" in
            1) printf '%s\n' 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B' ;;
            2) printf '%s\n' '0FC63DAF-8483-4772-8E79-3D69D8477DE4' ;;
            *) exit 93 ;;
        esac
        ;;
    --part-uuid)
        case "$3" in
            1) printf '%s\n' '22222222-2222-5222-8222-222222222222' ;;
            2) printf '%s\n' '33333333-3333-5333-8333-333333333333' ;;
            *) exit 94 ;;
        esac
        ;;
    *)
        printf 'unexpected sfdisk invocation: %s\n' "$*" >&2
        exit 95
        ;;
esac
MOCK_SFDISK
chmod 0755 "$MOCK_BIN/sfdisk"

printf 'contract: image region fingerprints\n'
env PATH="$MOCK_BIN:$PATH" \
    sh "$FINGERPRINT_SCRIPT" "$IMAGE" "$TEST_TMP/regions-1.txt" \
    > "$TEST_TMP/fingerprint-1.out"

grep -Fqx -- 'format_version=2' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'sector_size=512' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'image_sector_count=20' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'primary_gpt_region_start_sector=1' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'primary_gpt_region_sector_count=1' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'efi_partition_start_sector=2' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'efi_partition_sector_count=4' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'partition_gap_sector_count=2' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'root_partition_start_sector=8' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'root_partition_sector_count=8' "$TEST_TMP/regions-1.txt"
grep -Fqx -- 'backup_gpt_region_sector_count=4' "$TEST_TMP/regions-1.txt"
grep -Eq '^mbr_disk_signature_sha256=[0-9a-f]{64}$' "$TEST_TMP/regions-1.txt"
grep -Eq '^efi_partition_sha256=[0-9a-f]{64}$' "$TEST_TMP/regions-1.txt"
grep -Eq '^root_partition_sha256=[0-9a-f]{64}$' "$TEST_TMP/regions-1.txt"

printf 'contract: repeated fingerprints are stable\n'
env PATH="$MOCK_BIN:$PATH" \
    sh "$FINGERPRINT_SCRIPT" "$IMAGE" "$TEST_TMP/regions-2.txt" \
    > "$TEST_TMP/fingerprint-2.out"
cmp -s "$TEST_TMP/regions-1.txt" "$TEST_TMP/regions-2.txt"

printf 'contract: fingerprinting rejects overlapping partitions\n'
if env PATH="$MOCK_BIN:$PATH" MORIMIL_MOCK_OVERLAP=1 \
    sh "$FINGERPRINT_SCRIPT" "$IMAGE" "$TEST_TMP/overlap.txt" \
    > "$TEST_TMP/overlap.out" 2>&1
then
    printf 'error: fingerprint script accepted overlapping partitions\n' >&2
    exit 1
fi
grep -Fq -- 'EFI and root partitions overlap' "$TEST_TMP/overlap.out"

printf 'Image fingerprint contract tests passed.\n'
printf 'These tests use a synthetic image and do not prove real reproducibility.\n'
