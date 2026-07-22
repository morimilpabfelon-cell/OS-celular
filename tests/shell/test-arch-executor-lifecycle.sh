#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
LIFECYCLE=$ROOT_DIR/scripts/morimil-arch-executor.sh
PREPARE=$ROOT_DIR/scripts/prepare-arch-executor-rootfs.sh
POLICY=$ROOT_DIR/config/nspawn/morimil-arch.nspawn
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for path in "$LIFECYCLE" "$PREPARE" "$POLICY"; do
    [ -f "$path" ] || fail "required lifecycle file is missing: $path"
done

sh "$LIFECYCLE" help > "$TMP_DIR/help.txt"
for command_name in create start status stop destroy rebuild; do
    grep -Eq "^  ${command_name}[[:space:]]" "$TMP_DIR/help.txt" || fail "help is missing lifecycle command: $command_name"
done

if sh "$LIFECYCLE" unsupported > "$TMP_DIR/unsupported.out" 2> "$TMP_DIR/unsupported.err"; then
    fail 'unknown lifecycle command unexpectedly succeeded'
fi
grep -Fq 'unknown lifecycle command' "$TMP_DIR/unsupported.err" || fail 'unknown command error is unclear'

for forbidden in '--network-veth' '--bind=' '--bind-ro=' '--capability=' '--port='; do
    if grep -Fq -- "$forbidden" "$LIFECYCLE" "$PREPARE"; then
        fail "lifecycle implementation contains forbidden option: $forbidden"
    fi
done

if grep -Eq '(^|[^A-Za-z])pacman([^A-Za-z]|$)' "$LIFECYCLE" "$PREPARE"; then
    fail 'lifecycle implementation must not execute pacman'
fi

grep -Fq -- '--settings=trusted' "$LIFECYCLE" || fail 'start does not require trusted nspawn settings'
grep -Fq -- '--private-network' "$PREPARE" || fail 'ownership preparation lacks private networking'
grep -Fq -- '--private-users=pick' "$PREPARE" || fail 'ownership preparation lacks private users'
grep -Fq -- '--private-users-ownership=chown' "$PREPARE" || fail 'ownership preparation does not shift rootfs ownership'
grep -Fq 'NoNewPrivileges=yes' "$POLICY" || fail 'policy lacks NoNewPrivileges'
grep -Fq 'ReadOnly=yes' "$POLICY" || fail 'policy lacks read-only root'
grep -Fq 'Volatile=state' "$POLICY" || fail 'policy lacks volatile state'
grep -Fq 'Private=yes' "$POLICY" || fail 'policy lacks private network'
grep -Fq 'VirtualEthernet=no' "$POLICY" || fail 'policy permits a virtual Ethernet interface'

grep -Fq "fail 'executor must be stopped before destroy'" "$LIFECYCLE" || fail 'destroy does not refuse a running executor'
grep -Fq "fail 'executor service must be stopped before destroy'" "$LIFECYCLE" || fail 'destroy does not refuse an active service'
grep -Fq "fail 'installed policy differs from the repository policy; refusing to remove it'" "$LIFECYCLE" || fail 'destroy does not protect a modified installed policy'

rebuild_block=$(sed -n '/^[[:space:]]*rebuild)$/,/^[[:space:]]*;;/p' "$LIFECYCLE")
printf '%s\n' "$rebuild_block" | grep -Fq 'command_stop' || fail 'rebuild does not stop first'
printf '%s\n' "$rebuild_block" | grep -Fq 'command_destroy' || fail 'rebuild does not destroy the old rootfs'
printf '%s\n' "$rebuild_block" | grep -Fq 'command_create' || fail 'rebuild does not recreate the rootfs'

printf 'Arch executor lifecycle contract tests passed.\n'
