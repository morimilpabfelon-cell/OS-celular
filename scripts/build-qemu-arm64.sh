#!/bin/sh

set -eu
umask 022

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

BUILD_DIR=${BUILD_DIR:-"$SCRIPT_DIR/../build"}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-"$BUILD_DIR/morimil-trixie-arm64.raw"}
IMAGE_SIZE=${IMAGE_SIZE:-8G}
DEBIAN_SUITE=${DEBIAN_SUITE:-trixie}
FORCE=${FORCE:-0}

for required_command in \
    mmdebstrap-autopkgtest-build-qemu \
    sha256sum \
    mktemp \
    chmod \
    mv \
    rm \
    dirname \
    basename
do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

if [ -z "${DEBIAN_SNAPSHOT:-}" ]; then
    printf 'error: set DEBIAN_SNAPSHOT to a timestamp using YYYYMMDDThhmmssZ\n' >&2
    exit 1
fi

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    printf 'error: set SOURCE_DATE_EPOCH to the Unix timestamp associated with the archive state\n' >&2
    exit 1
fi

case "$DEBIAN_SNAPSHOT" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;;
    *)
        printf 'error: DEBIAN_SNAPSHOT must use the exact format YYYYMMDDThhmmssZ\n' >&2
        exit 1
        ;;
esac

case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*)
        printf 'error: SOURCE_DATE_EPOCH must be an unsigned Unix timestamp\n' >&2
        exit 1
        ;;
esac

case "$FORCE" in
    0|1) ;;
    *)
        printf 'error: FORCE must be 0 or 1\n' >&2
        exit 1
        ;;
esac

case "$DEBIAN_SUITE" in
    ''|-*|*[!A-Za-z0-9._-]*)
        printf 'error: DEBIAN_SUITE contains unsupported characters\n' >&2
        exit 1
        ;;
esac

case "$IMAGE_SIZE" in
    ''|-*)
        printf 'error: IMAGE_SIZE must not be empty or start with a hyphen\n' >&2
        exit 1
        ;;
esac

OUTPUT_DIR=$(dirname -- "$OUTPUT_IMAGE")
OUTPUT_NAME=$(basename -- "$OUTPUT_IMAGE")
CHECKSUM_FILE=$OUTPUT_IMAGE.sha256
METADATA_FILE=$OUTPUT_IMAGE.metadata

mkdir -p "$OUTPUT_DIR"

if [ "$FORCE" != 1 ]; then
    for existing_path in "$OUTPUT_IMAGE" "$CHECKSUM_FILE" "$METADATA_FILE"; do
        if [ -e "$existing_path" ]; then
            printf 'error: output already exists: %s; set FORCE=1 to replace it\n' "$existing_path" >&2
            exit 1
        fi
    done
fi

SNAPSHOT_MIRROR=https://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT/
TEMP_DIR=$(mktemp -d /tmp/morimil-arm64.XXXXXX)
chmod 0755 "$TEMP_DIR"
TEMP_IMAGE=$TEMP_DIR/$OUTPUT_NAME

trap 'rm -rf "$TEMP_DIR"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Building Morimil Debian validation image\n'
printf '  suite:      %s\n' "$DEBIAN_SUITE"
printf '  arch:       arm64\n'
printf '  snapshot:   %s\n' "$DEBIAN_SNAPSHOT"
printf '  mirror:     %s\n' "$SNAPSHOT_MIRROR"
printf '  image size: %s\n' "$IMAGE_SIZE"
printf '  output:     %s\n' "$OUTPUT_IMAGE"

export SOURCE_DATE_EPOCH

mmdebstrap-autopkgtest-build-qemu \
    --boot=efi \
    --arch=arm64 \
    --mirror="$SNAPSHOT_MIRROR" \
    --size="$IMAGE_SIZE" \
    "$DEBIAN_SUITE" \
    "$TEMP_IMAGE"

mv -f "$TEMP_IMAGE" "$OUTPUT_IMAGE"

(
    cd "$OUTPUT_DIR" || exit 1
    sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)

{
    printf 'format_version=1\n'
    printf 'artifact=%s\n' "$OUTPUT_NAME"
    printf 'debian_suite=%s\n' "$DEBIAN_SUITE"
    printf 'architecture=arm64\n'
    printf 'snapshot_requested=%s\n' "$DEBIAN_SNAPSHOT"
    printf 'snapshot_mirror=%s\n' "$SNAPSHOT_MIRROR"
    printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
    printf 'image_size=%s\n' "$IMAGE_SIZE"
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f="package=\${Package} version=\${Version}\n" mmdebstrap 2>/dev/null || true
    fi
} > "$METADATA_FILE"

printf 'Image created. This proves construction only, not successful boot.\n'
printf 'Checksum: %s\n' "$CHECKSUM_FILE"
printf 'Metadata: %s\n' "$METADATA_FILE"
