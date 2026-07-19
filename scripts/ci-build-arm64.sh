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
HELPER=/usr/bin/mmdebstrap-autopkgtest-build-qemu
HELPER_DEPENDENCIES='autopkgtest, dosfstools, e2fsprogs, fdisk, mount, mtools, passwd, uidmap, libarchive13, systemd-boot-efi:arm64, binutils-multiarch'
GUEST_APT_SOURCES_FILE=$BUILD_DIR/guest-apt-sources.sources

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

dpkg --add-architecture arm64
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
    binutils-multiarch \
    ca-certificates \
    coreutils \
    dosfstools \
    dpkg-dev \
    e2fsprogs \
    fdisk \
    gpg \
    libarchive13t64 \
    mmdebstrap \
    mount \
    mtools \
    passwd \
    qemu-efi-aarch64 \
    qemu-system-arm \
    qemu-user-binfmt \
    qemu-utils \
    systemd-boot-efi:arm64 \
    uidmap \
    uuid-runtime

for required_command in \
    dd \
    dpkg-architecture \
    dpkg-checkbuilddeps \
    gpg \
    mcopy \
    mke2fs \
    mkfs.vfat \
    newuidmap \
    qemu-img \
    qemu-system-aarch64 \
    sfdisk \
    sha256sum \
    stat \
    uuidgen
do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'error: required helper command not found: %s\n' "$required_command" >&2
        exit 1
    fi
done

for required_package in \
    binutils-multiarch \
    dpkg-dev \
    e2fsprogs \
    gpg \
    libarchive13t64 \
    mmdebstrap \
    systemd-boot-efi:arm64 \
    uuid-runtime
do
    package_status=$(dpkg-query -W -f='${db:Status-Status}' "$required_package" 2>/dev/null || true)
    if [ "$package_status" != installed ]; then
        printf 'error: required helper package is not installed: %s\n' "$required_package" >&2
        exit 1
    fi
done

if [ ! -x "$HELPER" ]; then
    printf 'error: Debian QEMU image helper is not executable: %s\n' "$HELPER" >&2
    exit 1
fi

if ! dpkg-checkbuilddeps -d "$HELPER_DEPENDENCIES" /dev/null; then
    printf 'error: Debian QEMU helper dependencies are incomplete\n' >&2
    exit 1
fi

cat > "$GUEST_APT_SOURCES_FILE" <<EOF_GUEST_SOURCES
Types: deb
URIs: http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT/
Suites: trixie
Components: main
Check-Valid-Until: no
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://snapshot.debian.org/archive/debian-security/$DEBIAN_SNAPSHOT/
Suites: trixie-security
Components: main
Check-Valid-Until: no
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF_GUEST_SOURCES

AUTOPKGTEST_APT_SOURCES=$(cat "$GUEST_APT_SOURCES_FILE")
export AUTOPKGTEST_APT_SOURCES
sha256sum "$GUEST_APT_SOURCES_FILE" > "$BUILD_DIR/guest-apt-sources.sha256"

sha256sum "$HELPER" > "$BUILD_DIR/mmdebstrap-helper.sha256"
{
    printf 'helper=%s\n' "$HELPER"
    printf 'helper_dependencies=%s\n' "$HELPER_DEPENDENCIES"
    printf 'foreign_architectures='
    dpkg --print-foreign-architectures | paste -sd, -
    printf 'autopkgtest_apt_sources_sha256='
    cut -d ' ' -f 1 "$BUILD_DIR/guest-apt-sources.sha256"
    grep -n -E 'dpkg-architecture|dpkg-checkbuilddeps|binutils-multiarch' "$HELPER" || true
} > "$BUILD_DIR/mmdebstrap-helper-preflight.txt"

BINFMT_DIRECTORY=/proc/sys/fs/binfmt_misc
BINFMT_REGISTER=$BINFMT_DIRECTORY/register
BINFMT_ENTRY=$BINFMT_DIRECTORY/qemu-aarch64
BINFMT_RULE_FILE=/usr/lib/binfmt.d/qemu-aarch64.conf

if [ ! -e "$BINFMT_REGISTER" ]; then
    mkdir -p "$BINFMT_DIRECTORY"
    mount -t binfmt_misc binfmt_misc "$BINFMT_DIRECTORY"
fi

if [ ! -r "$BINFMT_RULE_FILE" ]; then
    printf 'error: Debian qemu-aarch64 binfmt rule not found: %s\n' "$BINFMT_RULE_FILE" >&2
    exit 1
fi

if [ -e "$BINFMT_ENTRY" ]; then
    if ! grep -Fq 'enabled' "$BINFMT_ENTRY"; then
        printf '1' > "$BINFMT_ENTRY"
    fi
else
    binfmt_rule=
    while IFS= read -r candidate_rule || [ -n "$candidate_rule" ]; do
        case "$candidate_rule" in
            ''|'#'*|';'*) continue ;;
            *)
                binfmt_rule=$candidate_rule
                break
                ;;
        esac
    done < "$BINFMT_RULE_FILE"

    if [ -z "$binfmt_rule" ]; then
        printf 'error: no registration rule found in %s\n' "$BINFMT_RULE_FILE" >&2
        exit 1
    fi

    printf '%s' "$binfmt_rule" > "$BINFMT_REGISTER"
fi

if [ ! -r "$BINFMT_ENTRY" ] || ! grep -Fq 'enabled' "$BINFMT_ENTRY"; then
    printf 'error: qemu-aarch64 binfmt handler is not enabled\n' >&2
    exit 1
fi

if ! arch-test arm64; then
    printf 'error: arch-test could not execute ARM64 through binfmt_misc\n' >&2
    exit 1
fi

{
    printf 'container_image=%s\n' "$DEBIAN_CONTAINER_IMAGE"
    printf 'snapshot=%s\n' "$DEBIAN_SNAPSHOT"
    printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
    printf 'binfmt_rule_file=%s\n' "$BINFMT_RULE_FILE"
    printf 'guest_apt_sources=%s\n' "$GUEST_APT_SOURCES_FILE"
    printf 'foreign_architectures='
    dpkg --print-foreign-architectures | paste -sd, -
    cat "$BINFMT_ENTRY"
    cat /etc/os-release
    mmdebstrap --version
    qemu-system-aarch64 --version | head -n 1
    dpkg-query -W \
        autopkgtest \
        binutils-multiarch \
        dosfstools \
        dpkg-dev \
        e2fsprogs \
        fdisk \
        gpg \
        libarchive13t64 \
        mmdebstrap \
        mtools \
        passwd \
        qemu-efi-aarch64 \
        qemu-system-arm \
        qemu-user \
        qemu-user-binfmt \
        systemd-boot-efi:arm64 \
        uidmap \
        uuid-runtime
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

sh "$SCRIPT_DIR/fingerprint-qemu-image.sh" \
    "$OUTPUT_IMAGE" \
    "$BUILD_DIR/image-regions.txt"
cat "$BUILD_DIR/image-regions.txt"

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
