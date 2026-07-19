#!/bin/sh

set -eu
umask 022

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

BUILD_DIR=${BUILD_DIR:-"$SCRIPT_DIR/../build"}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-"$BUILD_DIR/morimil-trixie-arm64.raw"}
IMAGE_SIZE=${IMAGE_SIZE:-4G}
DEBIAN_CONTAINER_IMAGE=${DEBIAN_CONTAINER_IMAGE:-unknown}

if [ "$(id -u)" -ne 0 ]; then
    printf 'error: ci-build-arm64.sh must run as root inside the disposable Debian container\n' >&2
    exit 1
fi

if [ -z "${DEBIAN_SNAPSHOT:-}" ]; then
    printf 'error: DEBIAN_SNAPSHOT is required\n' >&2
    exit 1
fi

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    printf 'error: SOURCE_DATE_EPOCH is required\n' >&2
    exit 1
fi

case "$DEBIAN_SNAPSHOT" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;;
    *)
        printf 'error: DEBIAN_SNAPSHOT must use YYYYMMDDThhmmssZ\n' >&2
        exit 1
        ;;
esac

case "$SOURCE_DATE_EPOCH" in
    ''|*[!0-9]*)
        printf 'error: SOURCE_DATE_EPOCH must be an unsigned integer\n' >&2
        exit 1
        ;;
esac

mkdir -p "$BUILD_DIR"
export DEBIAN_FRONTEND=noninteractive

rm -f /etc/apt/sources.list
find /etc/apt/sources.list.d -type f -delete
cat > /etc/apt/sources.list.d/morimil-snapshot.sources <<EOF_SOURCES
Types: deb
URIs: http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT/
Suites: trixie
Components: main
Check-Valid-Until: no
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF_SOURCES

apt-get -o Acquire::Check-Valid-Until=false update
apt-get install --yes --no-install-recommends \
    arch-test \
    autopkgtest \
    binfmt-support \
    ca-certificates \
    coreutils \
    mmdebstrap \
    qemu-efi-aarch64 \
    qemu-system-arm \
    qemu-user-static \
    qemu-utils

update-binfmts --enable qemu-aarch64
if ! update-binfmts --display qemu-aarch64 | grep -Fq 'enabled'; then
    printf 'error: qemu-aarch64 binfmt handler is not enabled\n' >&2
    exit 1
fi

{
    printf 'container_image=%s\n' "$DEBIAN_CONTAINER_IMAGE"
    printf 'snapshot=%s\n' "$DEBIAN_SNAPSHOT"
    printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
    cat /etc/os-release
    mmdebstrap --version
    qemu-system-aarch64 --version | head -n 1
    dpkg-query -W \
        mmdebstrap \
        autopkgtest \
        qemu-efi-aarch64 \
        qemu-system-arm \
        qemu-user-static
} > "$BUILD_DIR/environment.txt"

set +e
BUILD_DIR=$BUILD_DIR \
OUTPUT_IMAGE=$OUTPUT_IMAGE \
IMAGE_SIZE=$IMAGE_SIZE \
FORCE=1 \
sh "$SCRIPT_DIR/build-qemu-arm64.sh" > "$BUILD_DIR/build.log" 2>&1
build_status=$?
set -e
cat "$BUILD_DIR/build.log"
if [ "$build_status" -ne 0 ]; then
    exit "$build_status"
fi

set +e
BUILD_DIR=$BUILD_DIR \
IMAGE=$OUTPUT_IMAGE \
MEMORY_MIB=1024 \
CPUS=2 \
timeout --signal=TERM 20m \
sh "$SCRIPT_DIR/run-qemu-arm64.sh" > "$BUILD_DIR/boot.log" 2>&1
boot_status=$?
set -e
cat "$BUILD_DIR/boot.log"
if [ "$boot_status" -ne 0 ]; then
    exit "$boot_status"
fi

sh "$SCRIPT_DIR/verify-boot-log.sh" "$BUILD_DIR/boot.log"
printf '%s\n' \
    'build_status=success' \
    'boot_status=success' \
    'proof=MORIMIL_BOOT_PROOF target=multi-user.target state=active' \
    > "$BUILD_DIR/validation-status.txt"
