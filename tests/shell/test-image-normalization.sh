#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

REPOSITORY_ROOT=$SCRIPT_DIR/../..
NORMALIZE_SCRIPT=$REPOSITORY_ROOT/scripts/normalize-qemu-image.sh
TEST_TMP=$(mktemp -d /tmp/morimil-normalization-tests.XXXXXX)
MOCK_BIN=$TEST_TMP/bin
MOCK_STATE=$TEST_TMP/state
MOCK_LOG=$TEST_TMP/sfdisk.log
IMAGE=$TEST_TMP/morimil.raw

trap 'rm -rf "$TEST_TMP"' 0
mkdir -p "$MOCK_BIN" "$MOCK_STATE"
printf 'mock-image\n' > "$IMAGE"

cat > "$MOCK_BIN/uuidgen" <<'MOCK_UUIDGEN'
#!/bin/sh
set -eu

name=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --name)
            name=$2
            shift 2
            ;;
        *) shift ;;
    esac
done

case "$name" in
    *'|gpt-disk') printf '%s\n' '11111111-1111-5111-8111-111111111111' ;;
    *'|efi-partition') printf '%s\n' '22222222-2222-5222-8222-222222222222' ;;
    *'|root-partition') printf '%s\n' '33333333-3333-5333-8333-333333333333' ;;
    *)
        printf 'unexpected uuid name: %s\n' "$name" >&2
        exit 90
        ;;
esac
MOCK_UUIDGEN

cat > "$MOCK_BIN/sfdisk" <<'MOCK_SFDISK'
#!/bin/sh
set -eu

: "${MORIMIL_MOCK_STATE:?}"
: "${MORIMIL_MOCK_SFDISK_LOG:?}"
printf '%s\n' "$*" >> "$MORIMIL_MOCK_SFDISK_LOG"

case "$1" in
    --part-type)
        partition=$3
        if [ "${MORIMIL_MOCK_BAD_LAYOUT:-0}" = 1 ] && [ "$partition" = 1 ]; then
            printf '%s\n' '0FC63DAF-8483-4772-8E79-3D69D8477DE4'
        elif [ "$partition" = 1 ]; then
            printf '%s\n' 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
        elif [ "$partition" = 2 ]; then
            printf '%s\n' '0FC63DAF-8483-4772-8E79-3D69D8477DE4'
        else
            exit 91
        fi
        ;;
    --disk-id)
        if [ "$#" -eq 2 ]; then
            if [ -f "$MORIMIL_MOCK_STATE/disk" ]; then
                cat "$MORIMIL_MOCK_STATE/disk"
            else
                printf '%s\n' 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'
            fi
        else
            printf '%s\n' "$3" > "$MORIMIL_MOCK_STATE/disk"
        fi
        ;;
    --part-uuid)
        partition=$3
        state_file=$MORIMIL_MOCK_STATE/part-$partition
        if [ "$#" -eq 3 ]; then
            if [ -f "$state_file" ]; then
                cat "$state_file"
            else
                printf '%s\n' 'BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB'
            fi
        else
            printf '%s\n' "$4" > "$state_file"
        fi
        ;;
    --verify) ;;
    *)
        printf 'unexpected sfdisk invocation: %s\n' "$*" >&2
        exit 92
        ;;
esac
MOCK_SFDISK

chmod 0755 "$MOCK_BIN/uuidgen" "$MOCK_BIN/sfdisk"

printf 'contract: deterministic GPT normalization\n'
env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_STATE="$MOCK_STATE" \
    MORIMIL_MOCK_SFDISK_LOG="$MOCK_LOG" \
    DEBIAN_SNAPSHOT=20260718T000000Z \
    SOURCE_DATE_EPOCH=1784332800 \
    DEBIAN_SUITE=trixie \
    IMAGE_SIZE=4G \
    sh "$NORMALIZE_SCRIPT" "$IMAGE" "$TEST_TMP/identifiers-1.txt" \
    > "$TEST_TMP/normalize-1.out"

grep -Fqx -- 'gpt_disk_uuid=11111111-1111-5111-8111-111111111111' "$TEST_TMP/identifiers-1.txt"
grep -Fqx -- 'efi_partition_type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B' "$TEST_TMP/identifiers-1.txt"
grep -Fqx -- 'efi_partition_uuid=22222222-2222-5222-8222-222222222222' "$TEST_TMP/identifiers-1.txt"
grep -Fqx -- 'root_partition_type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' "$TEST_TMP/identifiers-1.txt"
grep -Fqx -- 'root_partition_uuid=33333333-3333-5333-8333-333333333333' "$TEST_TMP/identifiers-1.txt"
grep -Fqx -- '--disk-id '"$IMAGE"' 11111111-1111-5111-8111-111111111111' "$MOCK_LOG"
grep -Fqx -- '--part-uuid '"$IMAGE"' 1 22222222-2222-5222-8222-222222222222' "$MOCK_LOG"
grep -Fqx -- '--part-uuid '"$IMAGE"' 2 33333333-3333-5333-8333-333333333333' "$MOCK_LOG"

printf 'contract: repeated normalization is stable\n'
env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_STATE="$MOCK_STATE" \
    MORIMIL_MOCK_SFDISK_LOG="$MOCK_LOG" \
    DEBIAN_SNAPSHOT=20260718T000000Z \
    SOURCE_DATE_EPOCH=1784332800 \
    DEBIAN_SUITE=trixie \
    IMAGE_SIZE=4G \
    sh "$NORMALIZE_SCRIPT" "$IMAGE" "$TEST_TMP/identifiers-2.txt" \
    > "$TEST_TMP/normalize-2.out"

cmp -s "$TEST_TMP/identifiers-1.txt" "$TEST_TMP/identifiers-2.txt"

printf 'contract: normalizer rejects unexpected partition layout\n'
if env \
    PATH="$MOCK_BIN:$PATH" \
    MORIMIL_MOCK_STATE="$MOCK_STATE" \
    MORIMIL_MOCK_SFDISK_LOG="$MOCK_LOG" \
    MORIMIL_MOCK_BAD_LAYOUT=1 \
    DEBIAN_SNAPSHOT=20260718T000000Z \
    SOURCE_DATE_EPOCH=1784332800 \
    sh "$NORMALIZE_SCRIPT" "$IMAGE" "$TEST_TMP/invalid-identifiers.txt" \
    > "$TEST_TMP/invalid-layout.out" 2>&1
then
    printf 'error: normalizer accepted an unexpected partition layout\n' >&2
    exit 1
fi

grep -Fq -- 'partition 1 is not the expected EFI System Partition' "$TEST_TMP/invalid-layout.out"

printf 'Image normalization contract tests passed.\n'
printf 'These tests use mocks and do not prove raw-image reproducibility.\n'
