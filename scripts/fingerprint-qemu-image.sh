#!/bin/sh

set -eu
umask 022
export LC_ALL=C

IMAGE=${1:-}
OUTPUT=${2:-}
SECTOR_SIZE=512

if [ -z "$IMAGE" ] || [ -z "$OUTPUT" ]; then
    printf 'usage: %s IMAGE OUTPUT\n' "$0" >&2
    exit 2
fi

if [ ! -f "$IMAGE" ] || [ ! -r "$IMAGE" ]; then
    printf 'error: image must be a readable regular file: %s\n' "$IMAGE" >&2
    exit 1
fi

for required_command in dd sfdisk sha256sum stat tr; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required fingerprint command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

require_unsigned_integer() {
    value=$1
    label=$2
    case "$value" in
        ''|*[!0-9]*)
            printf 'error: %s is not an unsigned integer: %s\n' "$label" "$value" >&2
            exit 1
            ;;
    esac
}

normalize_uuid() {
    tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

hash_sectors() {
    label=$1
    start=$2
    count=$3
    digest=$(dd if="$IMAGE" bs=$SECTOR_SIZE skip="$start" count="$count" status=none | sha256sum)
    digest=${digest%% *}
    printf '%s_start_sector=%s\n' "$label" "$start"
    printf '%s_sector_count=%s\n' "$label" "$count"
    printf '%s_sha256=%s\n' "$label" "$digest"
}

hash_bytes() {
    label=$1
    start=$2
    count=$3
    digest=$(dd if="$IMAGE" bs=1 skip="$start" count="$count" status=none | sha256sum)
    digest=${digest%% *}
    printf '%s_byte_offset=%s\n' "$label" "$start"
    printf '%s_byte_count=%s\n' "$label" "$count"
    printf '%s_sha256=%s\n' "$label" "$digest"
}

image_size_bytes=$(stat -c '%s' "$IMAGE")
require_unsigned_integer "$image_size_bytes" image_size_bytes

if [ $((image_size_bytes % SECTOR_SIZE)) -ne 0 ]; then
    printf 'error: image size is not divisible by %s bytes: %s\n' \
        "$SECTOR_SIZE" "$image_size_bytes" >&2
    exit 1
fi

image_sectors=$((image_size_bytes / SECTOR_SIZE))
efi_start=$(sfdisk --part-start "$IMAGE" 1 | tr -d '[:space:]')
efi_size=$(sfdisk --part-size "$IMAGE" 1 | tr -d '[:space:]')
root_start=$(sfdisk --part-start "$IMAGE" 2 | tr -d '[:space:]')
root_size=$(sfdisk --part-size "$IMAGE" 2 | tr -d '[:space:]')

require_unsigned_integer "$efi_start" efi_start
require_unsigned_integer "$efi_size" efi_size
require_unsigned_integer "$root_start" root_start
require_unsigned_integer "$root_size" root_size

if [ "$efi_size" -eq 0 ] || [ "$root_size" -eq 0 ]; then
    printf 'error: partition sizes must be greater than zero\n' >&2
    exit 1
fi

efi_end=$((efi_start + efi_size))
root_end=$((root_start + root_size))

if [ "$efi_start" -lt 2 ]; then
    printf 'error: EFI partition overlaps primary GPT structures\n' >&2
    exit 1
fi

if [ "$efi_end" -gt "$root_start" ]; then
    printf 'error: EFI and root partitions overlap\n' >&2
    exit 1
fi

if [ "$root_end" -gt "$image_sectors" ]; then
    printf 'error: root partition extends beyond image size\n' >&2
    exit 1
fi

whole_digest=$(sha256sum "$IMAGE")
whole_digest=${whole_digest%% *}
disk_uuid=$(sfdisk --disk-id "$IMAGE" | normalize_uuid)
efi_type=$(sfdisk --part-type "$IMAGE" 1 | normalize_uuid)
efi_uuid=$(sfdisk --part-uuid "$IMAGE" 1 | normalize_uuid)
root_type=$(sfdisk --part-type "$IMAGE" 2 | normalize_uuid)
root_uuid=$(sfdisk --part-uuid "$IMAGE" 2 | normalize_uuid)

{
    printf 'format_version=1\n'
    printf 'sector_size=%s\n' "$SECTOR_SIZE"
    printf 'image_size_bytes=%s\n' "$image_size_bytes"
    printf 'image_sector_count=%s\n' "$image_sectors"
    printf 'image_sha256=%s\n' "$whole_digest"
    printf 'gpt_disk_uuid=%s\n' "$disk_uuid"
    printf 'efi_partition_type=%s\n' "$efi_type"
    printf 'efi_partition_uuid=%s\n' "$efi_uuid"
    printf 'root_partition_type=%s\n' "$root_type"
    printf 'root_partition_uuid=%s\n' "$root_uuid"
    hash_bytes mbr_bootstrap 0 440
    hash_bytes mbr_disk_signature 440 4
    hash_bytes mbr_reserved 444 2
    hash_bytes mbr_partition_table 446 64
    hash_bytes mbr_magic 510 2
    hash_sectors primary_gpt_header 1 1
    hash_sectors primary_gpt_array 2 $((efi_start - 2))
    hash_sectors efi_partition "$efi_start" "$efi_size"
    hash_sectors partition_gap "$efi_end" $((root_start - efi_end))
    hash_sectors root_partition "$root_start" "$root_size"
    hash_sectors backup_gpt_region "$root_end" $((image_sectors - root_end))
} > "$OUTPUT"

printf 'Image region fingerprints created.\n'
printf 'Fingerprints: %s\n' "$OUTPUT"
