#!/bin/sh

set -eu
umask 022
export LC_ALL=C

IMAGE=${1:-}
IDENTIFIERS_FILE=${2:-}
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
IMAGE_SIZE=${IMAGE_SIZE:-unknown}

if [ -z "$IMAGE" ] || [ -z "$IDENTIFIERS_FILE" ]; then
    printf 'usage: %s IMAGE IDENTIFIERS_FILE\n' "$0" >&2
    exit 2
fi

if [ ! -f "$IMAGE" ] || [ ! -r "$IMAGE" ] || [ ! -w "$IMAGE" ]; then
    printf 'error: image must be a readable and writable regular file: %s\n' "$IMAGE" >&2
    exit 1
fi

if [ -z "${DEBIAN_SNAPSHOT:-}" ]; then
    printf 'error: DEBIAN_SNAPSHOT is required for deterministic identifiers\n' >&2
    exit 1
fi

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    printf 'error: SOURCE_DATE_EPOCH is required for deterministic identifiers\n' >&2
    exit 1
fi

for required_command in sfdisk uuidgen sha256sum tr; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required normalization command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

normalize_uuid() {
    tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

validate_uuid() {
    candidate_uuid=$1
    case "$candidate_uuid" in
        ????????-????-????-????-????????????) ;;
        *)
            printf 'error: generated value is not a UUID: %s\n' "$candidate_uuid" >&2
            exit 1
            ;;
    esac
    case "$candidate_uuid" in
        *[!0-9A-F-]*)
            printf 'error: generated UUID contains unsupported characters: %s\n' "$candidate_uuid" >&2
            exit 1
            ;;
    esac
}

EFI_PARTITION_TYPE=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
ROOT_PARTITION_TYPE=B921B045-1DF0-41C3-AF44-4C6F280D3FAE

actual_efi_type=$(sfdisk --part-type "$IMAGE" 1 | normalize_uuid)
actual_root_type=$(sfdisk --part-type "$IMAGE" 2 | normalize_uuid)

if [ "$actual_efi_type" != "$EFI_PARTITION_TYPE" ]; then
    printf 'error: partition 1 is not the expected EFI System Partition: %s\n' "$actual_efi_type" >&2
    exit 1
fi

if [ "$actual_root_type" != "$ROOT_PARTITION_TYPE" ]; then
    printf 'error: partition 2 is not the expected ARM64 root partition: %s\n' "$actual_root_type" >&2
    exit 1
fi

IDENTIFIER_SEED="morimil-qemu-arm64|suite=$DEBIAN_SUITE|snapshot=$DEBIAN_SNAPSHOT|source_date_epoch=$SOURCE_DATE_EPOCH|image_size=$IMAGE_SIZE"
SEED_SHA256=$(printf '%s' "$IDENTIFIER_SEED" | sha256sum)
SEED_SHA256=${SEED_SHA256%% *}

GPT_DISK_UUID=$(uuidgen --sha1 --namespace @dns --name "$IDENTIFIER_SEED|gpt-disk" | normalize_uuid)
EFI_PARTITION_UUID=$(uuidgen --sha1 --namespace @dns --name "$IDENTIFIER_SEED|efi-partition" | normalize_uuid)
ROOT_PARTITION_UUID=$(uuidgen --sha1 --namespace @dns --name "$IDENTIFIER_SEED|root-partition" | normalize_uuid)

validate_uuid "$GPT_DISK_UUID"
validate_uuid "$EFI_PARTITION_UUID"
validate_uuid "$ROOT_PARTITION_UUID"

sfdisk --disk-id "$IMAGE" "$GPT_DISK_UUID" >/dev/null
sfdisk --part-uuid "$IMAGE" 1 "$EFI_PARTITION_UUID" >/dev/null
sfdisk --part-uuid "$IMAGE" 2 "$ROOT_PARTITION_UUID" >/dev/null
sfdisk --verify "$IMAGE" >/dev/null

actual_disk_uuid=$(sfdisk --disk-id "$IMAGE" | normalize_uuid)
actual_efi_uuid=$(sfdisk --part-uuid "$IMAGE" 1 | normalize_uuid)
actual_root_uuid=$(sfdisk --part-uuid "$IMAGE" 2 | normalize_uuid)

if [ "$actual_disk_uuid" != "$GPT_DISK_UUID" ]; then
    printf 'error: GPT disk UUID verification failed: expected %s, got %s\n' \
        "$GPT_DISK_UUID" "$actual_disk_uuid" >&2
    exit 1
fi

if [ "$actual_efi_uuid" != "$EFI_PARTITION_UUID" ]; then
    printf 'error: EFI partition UUID verification failed: expected %s, got %s\n' \
        "$EFI_PARTITION_UUID" "$actual_efi_uuid" >&2
    exit 1
fi

if [ "$actual_root_uuid" != "$ROOT_PARTITION_UUID" ]; then
    printf 'error: root partition UUID verification failed: expected %s, got %s\n' \
        "$ROOT_PARTITION_UUID" "$actual_root_uuid" >&2
    exit 1
fi

{
    printf 'format_version=1\n'
    printf 'identifier_seed_sha256=%s\n' "$SEED_SHA256"
    printf 'gpt_disk_uuid=%s\n' "$GPT_DISK_UUID"
    printf 'efi_partition_type=%s\n' "$EFI_PARTITION_TYPE"
    printf 'efi_partition_uuid=%s\n' "$EFI_PARTITION_UUID"
    printf 'root_partition_type=%s\n' "$ROOT_PARTITION_TYPE"
    printf 'root_partition_uuid=%s\n' "$ROOT_PARTITION_UUID"
    printf 'efi_filesystem_creation=mkfs.fat_--invariant_by_debian_helper\n'
} > "$IDENTIFIERS_FILE"

printf 'Deterministic GPT identifiers applied.\n'
printf 'Identifiers: %s\n' "$IDENTIFIERS_FILE"
