#!/bin/sh

set -eu
umask 022
export LC_ALL=C
export TZ=UTC
export DEBIAN_FRONTEND=noninteractive

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

BUILD_DIR=${BUILD_DIR:-"$SCRIPT_DIR/../build"}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-"$BUILD_DIR/morimil-trixie-arm64.raw"}
CHECKSUM_FILE=$OUTPUT_IMAGE.sha256
ENVIRONMENT_FILE=$BUILD_DIR/ext4-inspection-environment.txt

if [ "$(id -u)" -ne 0 ]; then
    printf 'error: ci-inspect-ext4.sh must run as root inside the disposable Debian container\n' >&2
    exit 1
fi

if [ ! -f "$OUTPUT_IMAGE" ]; then
    printf 'error: image not found for ext4 inspection: %s\n' "$OUTPUT_IMAGE" >&2
    exit 1
fi

if [ ! -f "$CHECKSUM_FILE" ]; then
    printf 'error: checksum manifest not found for ext4 inspection: %s\n' "$CHECKSUM_FILE" >&2
    exit 1
fi

apt-get install --yes --no-install-recommends python3

for required_command in dumpe2fs losetup mount python3 sha256sum umount; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required ext4 diagnostic command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

(
    cd "$BUILD_DIR" || exit 1
    sha256sum -c "${OUTPUT_IMAGE##*/}.sha256"
)

{
    printf 'python='
    python3 --version
    dpkg-query -W python3 python3-minimal e2fsprogs mount util-linux
} > "$ENVIRONMENT_FILE"

sh "$SCRIPT_DIR/inspect-ext4-root.sh" "$OUTPUT_IMAGE" "$BUILD_DIR"
cat "$BUILD_DIR/ext4-inspection-status.txt"
printf 'ext4_inspection_status=success\n' >> "$BUILD_DIR/validation-status.txt"

printf 'Ext4 diagnostic evidence created.\n'
printf 'Environment: %s\n' "$ENVIRONMENT_FILE"
