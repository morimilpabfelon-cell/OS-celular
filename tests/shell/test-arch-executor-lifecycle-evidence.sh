#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
CHECKER=$ROOT_DIR/scripts/check-arch-executor-lifecycle-evidence.sh
TMP_DIR=$(mktemp -d)
EVIDENCE=$TMP_DIR/evidence
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$EVIDENCE"
SHA=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a

cat > "$EVIDENCE/host-before.env" <<'EOF_HOST'
boot_id=boot-id-1
sentinel_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
network_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
net_namespace=net:[1]
pid1_comm=systemd
architecture=aarch64
EOF_HOST
cp "$EVIDENCE/host-before.env" "$EVIDENCE/host-after.env"

cat > "$EVIDENCE/create-command.env" <<'EOF_CREATE'
machine=morimil-arch
state=stopped
result=created
EOF_CREATE
cat > "$EVIDENCE/created-status.env" <<EOF_CREATED
machine=morimil-arch
created=yes
running=no
state=stopped
leader=
rootfs_sha256=$SHA
uid_shift=65536
EOF_CREATED

cat > "$EVIDENCE/generation-1-rootfs-source.env" <<EOF_SOURCE
MORIMIL_ROOTFS_SHA256=$SHA
EOF_SOURCE
cp "$EVIDENCE/generation-1-rootfs-source.env" "$EVIDENCE/generation-2-rootfs-source.env"

for label in first second; do
    cat > "$EVIDENCE/$label-start-command.env" <<'EOF_START'
machine=morimil-arch
state=running
result=started
EOF_START
    cat > "$EVIDENCE/$label-running-status.env" <<EOF_RUNNING
machine=morimil-arch
created=yes
running=yes
state=running
leader=1234
rootfs_sha256=$SHA
uid_shift=65536
EOF_RUNNING
    cat > "$EVIDENCE/$label-ready.env" <<'EOF_READY'
pid1_comm=systemd
network_interfaces=lo
EOF_READY
    printf '         0      65536      65536\n' > "$EVIDENCE/$label-uid-map.txt"
    printf 'ro,nosuid,nodev\n' > "$EVIDENCE/$label-root-options.txt"
    printf 'tmpfs\n' > "$EVIDENCE/$label-var-fstype.txt"
    printf 'lo\n' > "$EVIDENCE/$label-network-interfaces.txt"
    printf '1\n' > "$EVIDENCE/$label-no-new-privileges.txt"
    cat > "$EVIDENCE/$label-netns.env" <<'EOF_NETNS'
host=net:[1]
container=net:[2]
EOF_NETNS
done

cat > "$EVIDENCE/first-stop-command.env" <<'EOF_STOP'
machine=morimil-arch
state=stopped
result=stopped
EOF_STOP
cat > "$EVIDENCE/first-stopped-status.env" <<EOF_STOPPED
machine=morimil-arch
created=yes
running=no
state=stopped
leader=
rootfs_sha256=$SHA
uid_shift=65536
EOF_STOPPED

cat > "$EVIDENCE/rebuild-command.env" <<'EOF_REBUILD'
machine=morimil-arch
state=stopped
result=stopped
machine=morimil-arch
state=absent
result=destroyed
machine=morimil-arch
state=stopped
result=created
EOF_REBUILD
cat > "$EVIDENCE/rebuilt-status.env" <<EOF_REBUILT
machine=morimil-arch
created=yes
running=no
state=stopped
leader=
rootfs_sha256=$SHA
uid_shift=65536
EOF_REBUILT

cat > "$EVIDENCE/second-stop-command.env" <<'EOF_STOP2'
machine=morimil-arch
state=stopped
result=stopped
EOF_STOP2
cat > "$EVIDENCE/destroy-command.env" <<'EOF_DESTROY'
machine=morimil-arch
state=absent
result=destroyed
EOF_DESTROY
cat > "$EVIDENCE/destroyed-status.env" <<'EOF_ABSENT'
machine=morimil-arch
created=no
running=no
state=absent
leader=
rootfs_sha256=
uid_shift=
EOF_ABSENT

cat > "$EVIDENCE/lifecycle-summary.env" <<'EOF_SUMMARY'
host_architecture=aarch64
create=yes
first_start=yes
first_stop=yes
rebuild=yes
second_start=yes
second_stop=yes
destroy=yes
host_unchanged=yes
rootfs_removed=yes
state_removed=yes
policy_removed=yes
EOF_SUMMARY

sh "$CHECKER" "$EVIDENCE" > "$TMP_DIR/valid.out"
grep -Fq 'lifecycle evidence passed' "$TMP_DIR/valid.out" || fail 'valid lifecycle evidence was not accepted'

printf 'eth0\n' > "$EVIDENCE/second-network-interfaces.txt"
if sh "$CHECKER" "$EVIDENCE" > "$TMP_DIR/network.out" 2> "$TMP_DIR/network.err"; then
    fail 'non-loopback lifecycle evidence unexpectedly passed'
fi
grep -Fq 'network listing is not loopback-only' "$TMP_DIR/network.err" || fail 'network evidence failure is unclear'
printf 'lo\n' > "$EVIDENCE/second-network-interfaces.txt"

cat > "$EVIDENCE/generation-2-rootfs-source.env" <<'EOF_BAD_SOURCE'
MORIMIL_ROOTFS_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF_BAD_SOURCE
if sh "$CHECKER" "$EVIDENCE" > "$TMP_DIR/hash.out" 2> "$TMP_DIR/hash.err"; then
    fail 'mismatched rebuild checksum unexpectedly passed'
fi
grep -Fq 'different rootfs SHA-256' "$TMP_DIR/hash.err" || fail 'checksum evidence failure is unclear'

printf 'Arch executor lifecycle evidence tests passed.\n'
