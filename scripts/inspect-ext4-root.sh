#!/bin/sh

set -eu
umask 077
export LC_ALL=C
export TZ=UTC

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

IMAGE=${1:-}
OUTPUT_DIR=${2:-}
MANIFEST_SCRIPT=${MANIFEST_SCRIPT:-"$SCRIPT_DIR/manifest-ext4-tree.py"}
EXPECTED_SECTOR_SIZE=512
ROOT_PARTITION_TYPE=0FC63DAF-8483-4772-8E79-3D69D8477DE4

if [ -z "$IMAGE" ] || [ -z "$OUTPUT_DIR" ]; then
    printf 'usage: %s IMAGE OUTPUT_DIR\n' "$0" >&2
    exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
    printf 'error: ext4 inspection requires root for loop and mount operations\n' >&2
    exit 1
fi

if [ ! -f "$IMAGE" ] || [ ! -r "$IMAGE" ]; then
    printf 'error: image must be a readable regular file: %s\n' "$IMAGE" >&2
    exit 1
fi

if [ ! -f "$MANIFEST_SCRIPT" ] || [ ! -r "$MANIFEST_SCRIPT" ]; then
    printf 'error: manifest script is not readable: %s\n' "$MANIFEST_SCRIPT" >&2
    exit 1
fi

for required_command in \
    awk \
    cut \
    dumpe2fs \
    id \
    losetup \
    mkdir \
    mktemp \
    mount \
    python3 \
    rm \
    sfdisk \
    sha256sum \
    tr \
    umount
do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required ext4 inspection command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"
SUPERBLOCK_FILE=$OUTPUT_DIR/ext4-superblock.txt
GROUPS_FILE=$OUTPUT_DIR/ext4-groups.txt
TREE_FILE=$OUTPUT_DIR/ext4-tree.jsonl
TREE_CHECKSUM_FILE=$OUTPUT_DIR/ext4-tree.sha256
STATUS_FILE=$OUTPUT_DIR/ext4-inspection-status.txt

for output_path in \
    "$SUPERBLOCK_FILE" \
    "$GROUPS_FILE" \
    "$TREE_FILE" \
    "$TREE_CHECKSUM_FILE" \
    "$STATUS_FILE"
do
    if [ -e "$output_path" ]; then
        printf 'error: ext4 inspection output already exists: %s\n' "$output_path" >&2
        exit 1
    fi
done

layout_dump=$(sfdisk --dump "$IMAGE")
partition_label=$(printf '%s\n' "$layout_dump" | awk -F: '$1 == "label" {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
partition_unit=$(printf '%s\n' "$layout_dump" | awk -F: '$1 == "unit" {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
sector_size=$(printf '%s\n' "$layout_dump" | awk -F: '$1 == "sector-size" {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
partition_count=$(printf '%s\n' "$layout_dump" | awk '/:[[:space:]]*start[[:space:]]*=/ {count += 1} END {print count + 0}')
root_start=$(printf '%s\n' "$layout_dump" | awk -F'[=,]' '
    /:[[:space:]]*start[[:space:]]*=/ {
        partition += 1
        if (partition == 2) {
            for (field = 1; field < NF; field += 1) {
                key = $field
                sub(/^.*:[[:space:]]*/, "", key)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                if (key == "start") {
                    value = $(field + 1)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                    print value
                    exit
                }
            }
        }
    }
')
root_size=$(printf '%s\n' "$layout_dump" | awk -F'[=,]' '
    /:[[:space:]]*start[[:space:]]*=/ {
        partition += 1
        if (partition == 2) {
            for (field = 1; field < NF; field += 1) {
                key = $field
                sub(/^.*:[[:space:]]*/, "", key)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                if (key == "size") {
                    value = $(field + 1)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                    print value
                    exit
                }
            }
        }
    }
')

if [ "$partition_label" != gpt ]; then
    printf 'error: expected GPT partition table, got: %s\n' "$partition_label" >&2
    exit 1
fi

if [ "$partition_unit" != sectors ]; then
    printf 'error: expected partition units in sectors, got: %s\n' "$partition_unit" >&2
    exit 1
fi

case "$sector_size:$partition_count:$root_start:$root_size" in
    *[!0-9:]*|*::*|:*|*:)
        printf 'error: invalid numeric partition metadata\n' >&2
        exit 1
        ;;
esac

if [ "$sector_size" -ne "$EXPECTED_SECTOR_SIZE" ]; then
    printf 'error: expected %s-byte sectors, got: %s\n' "$EXPECTED_SECTOR_SIZE" "$sector_size" >&2
    exit 1
fi

if [ "$partition_count" -ne 2 ]; then
    printf 'error: expected exactly two partitions, got: %s\n' "$partition_count" >&2
    exit 1
fi

if [ "$root_size" -eq 0 ]; then
    printf 'error: root partition size must be greater than zero\n' >&2
    exit 1
fi

actual_root_type=$(sfdisk --part-type "$IMAGE" 2 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
if [ "$actual_root_type" != "$ROOT_PARTITION_TYPE" ]; then
    printf 'error: unexpected root partition type: %s\n' "$actual_root_type" >&2
    exit 1
fi

root_offset_bytes=$((root_start * EXPECTED_SECTOR_SIZE))
root_size_bytes=$((root_size * EXPECTED_SECTOR_SIZE))
image_sha256_before=$(sha256sum "$IMAGE")
image_sha256_before=${image_sha256_before%% *}

MOUNT_DIR=$(mktemp -d /tmp/morimil-ext4-inspection.XXXXXX)
LOOP_DEVICE=
MOUNTED=0

cleanup() {
    cleanup_status=$?
    trap - 0 HUP INT TERM
    set +e
    if [ "$MOUNTED" = 1 ]; then
        umount "$MOUNT_DIR"
    fi
    if [ -n "$LOOP_DEVICE" ]; then
        losetup --detach "$LOOP_DEVICE"
    fi
    rm -rf "$MOUNT_DIR"
    exit "$cleanup_status"
}

trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

LOOP_DEVICE=$(losetup \
    --find \
    --show \
    --read-only \
    --offset "$root_offset_bytes" \
    --sizelimit "$root_size_bytes" \
    "$IMAGE")

loop_read_only=$(losetup --list --noheadings --output RO "$LOOP_DEVICE" | tr -d '[:space:]')
if [ "$loop_read_only" != 1 ]; then
    printf 'error: loop device is not read-only: %s\n' "$LOOP_DEVICE" >&2
    exit 1
fi

dumpe2fs -h "$LOOP_DEVICE" > "$SUPERBLOCK_FILE" 2>&1
dumpe2fs -g "$LOOP_DEVICE" > "$GROUPS_FILE" 2>&1

mount -t ext4 -o ro,noload,nodev,nosuid,noexec "$LOOP_DEVICE" "$MOUNT_DIR"
MOUNTED=1
python3 "$MANIFEST_SCRIPT" "$MOUNT_DIR" "$TREE_FILE"
(
    cd "$OUTPUT_DIR" || exit 1
    sha256sum ext4-tree.jsonl > ext4-tree.sha256
)

umount "$MOUNT_DIR"
MOUNTED=0
losetup --detach "$LOOP_DEVICE"
LOOP_DEVICE=

image_sha256_after=$(sha256sum "$IMAGE")
image_sha256_after=${image_sha256_after%% *}
if [ "$image_sha256_after" != "$image_sha256_before" ]; then
    printf 'error: image changed during read-only ext4 inspection\n' >&2
    exit 1
fi

tree_manifest_sha256=$(cut -d ' ' -f 1 "$TREE_CHECKSUM_FILE")
{
    printf 'format_version=1\n'
    printf 'image_sha256_before=%s\n' "$image_sha256_before"
    printf 'image_sha256_after=%s\n' "$image_sha256_after"
    printf 'root_start_sector=%s\n' "$root_start"
    printf 'root_sector_count=%s\n' "$root_size"
    printf 'root_offset_bytes=%s\n' "$root_offset_bytes"
    printf 'root_size_bytes=%s\n' "$root_size_bytes"
    printf 'loop_read_only=1\n'
    printf 'mount_options=ro,noload,nodev,nosuid,noexec\n'
    printf 'tree_manifest_sha256=%s\n' "$tree_manifest_sha256"
} > "$STATUS_FILE"

printf 'Read-only ext4 inspection completed.\n'
printf 'Status: %s\n' "$STATUS_FILE"
