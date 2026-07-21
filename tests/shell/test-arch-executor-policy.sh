#!/bin/sh

set -eu

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
CHECK="$ROOT_DIR/scripts/check-arch-executor-policy.sh"
VALID="$ROOT_DIR/config/nspawn/morimil-arch.nspawn"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

expect_reject() {
    name=$1
    file=$2
    if sh "$CHECK" "$file" >/dev/null 2>&1; then
        fail "$name was accepted"
    fi
}

sh "$CHECK" "$VALID" >/dev/null

sed 's/^Private=yes$/Private=no/' "$VALID" > "$TMP_DIR/network-enabled.nspawn"
expect_reject 'shared host networking' "$TMP_DIR/network-enabled.nspawn"

sed 's/^PrivateUsers=pick$/PrivateUsers=identity/' "$VALID" > "$TMP_DIR/identity-users.nspawn"
expect_reject 'identity UID mapping' "$TMP_DIR/identity-users.nspawn"

{
    cat "$VALID"
    printf '\nCapability=all\n'
} > "$TMP_DIR/capabilities.nspawn"
expect_reject 'capability grant' "$TMP_DIR/capabilities.nspawn"

{
    cat "$VALID"
    printf '\nBind=/dev:/dev\n'
} > "$TMP_DIR/device-bind.nspawn"
expect_reject 'host device bind' "$TMP_DIR/device-bind.nspawn"

{
    cat "$VALID"
    printf '\nReadOnly=no\n'
} > "$TMP_DIR/root-write.nspawn"
expect_reject 'writable root override' "$TMP_DIR/root-write.nspawn"

expect_reject 'missing configuration' "$TMP_DIR/missing.nspawn"

printf 'Arch executor policy contract tests passed.\n'
