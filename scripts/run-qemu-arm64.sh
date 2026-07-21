#!/bin/sh

set -eu
umask 022

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

BUILD_DIR=${BUILD_DIR:-"$SCRIPT_DIR/../build"}
IMAGE=${IMAGE:-"$BUILD_DIR/morimil-trixie-arm64.raw"}
FIRMWARE_CODE=${FIRMWARE_CODE:-/usr/share/AAVMF/AAVMF_CODE.fd}
FIRMWARE_VARS_TEMPLATE=${FIRMWARE_VARS_TEMPLATE:-/usr/share/AAVMF/AAVMF_VARS.fd}
FIRMWARE_VARS=${FIRMWARE_VARS:-"$BUILD_DIR/AAVMF_VARS.fd"}
MEMORY_MIB=${MEMORY_MIB:-2048}
CPUS=${CPUS:-2}
ALLOW_UNVERIFIED_IMAGE=${ALLOW_UNVERIFIED_IMAGE:-0}

for required_command in qemu-system-aarch64 sha256sum cp dirname basename; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

if [ ! -f "$IMAGE" ]; then
    printf 'error: image not found: %s\n' "$IMAGE" >&2
    exit 1
fi

if [ ! -r "$FIRMWARE_CODE" ]; then
    printf 'error: AArch64 UEFI code firmware not found: %s\n' "$FIRMWARE_CODE" >&2
    exit 1
fi

if [ ! -r "$FIRMWARE_VARS_TEMPLATE" ]; then
    printf 'error: AArch64 UEFI variable template not found: %s\n' "$FIRMWARE_VARS_TEMPLATE" >&2
    exit 1
fi

case "$MEMORY_MIB" in
    ''|*[!0-9]*|0)
        printf 'error: MEMORY_MIB must be a positive integer\n' >&2
        exit 1
        ;;
esac

case "$CPUS" in
    ''|*[!0-9]*|0)
        printf 'error: CPUS must be a positive integer\n' >&2
        exit 1
        ;;
esac

case "$ALLOW_UNVERIFIED_IMAGE" in
    0|1) ;;
    *)
        printf 'error: ALLOW_UNVERIFIED_IMAGE must be 0 or 1\n' >&2
        exit 1
        ;;
esac

if [ -f "$IMAGE.sha256" ]; then
    IMAGE_DIR=$(dirname -- "$IMAGE")
    IMAGE_NAME=$(basename -- "$IMAGE")
    (
        cd "$IMAGE_DIR" || exit 1
        sha256sum -c "$IMAGE_NAME.sha256"
    )
elif [ "$ALLOW_UNVERIFIED_IMAGE" = 1 ]; then
    printf 'warning: starting an image without a checksum manifest\n' >&2
else
    printf 'error: checksum manifest not found: %s.sha256\n' "$IMAGE" >&2
    exit 1
fi

if [ "$FIRMWARE_VARS" = "$FIRMWARE_VARS_TEMPLATE" ]; then
    printf 'error: FIRMWARE_VARS must not overwrite the firmware template\n' >&2
    exit 1
fi

mkdir -p "$(dirname -- "$FIRMWARE_VARS")"
cp "$FIRMWARE_VARS_TEMPLATE" "$FIRMWARE_VARS"

printf 'Starting QEMU ARM64 validation VM\n'
printf '  image:   %s\n' "$IMAGE"
printf '  machine: virt\n'
printf '  cpu:     cortex-a57\n'
printf '  accel:   tcg\n'
printf '  memory:  %s MiB\n' "$MEMORY_MIB"
printf '  cpus:    %s\n' "$CPUS"
printf '  network: disabled\n'
printf 'Exit QEMU with Ctrl-a x.\n'

exec qemu-system-aarch64 \
    -machine virt,accel=tcg \
    -cpu cortex-a57 \
    -smp "$CPUS" \
    -m "$MEMORY_MIB" \
    -nographic \
    -no-reboot \
    -snapshot \
    -nic none \
    -drive if=pflash,format=raw,readonly=on,file="$FIRMWARE_CODE" \
    -drive if=pflash,format=raw,file="$FIRMWARE_VARS" \
    -drive if=virtio,format=raw,file="$IMAGE"
