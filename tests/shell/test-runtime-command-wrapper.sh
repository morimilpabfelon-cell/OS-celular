#!/bin/sh

set -eu
umask 077

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd)
WRAPPER=$ROOT_DIR/scripts/ci-runtime-command-wrapper.sh
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' 0 HUP INT TERM

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ -f "$WRAPPER" ] || fail "runtime command wrapper is missing: $WRAPPER"
[ -x /usr/bin/systemctl ] || fail '/usr/bin/systemctl is required for the wrapper contract test'

ln -s "$WRAPPER" "$TMP_DIR/systemctl"
COMMAND_LOG=$TMP_DIR/commands.log

version_output=$(
    ARCH_EXECUTOR_COMMAND_LOG=$COMMAND_LOG \
        sh "$TMP_DIR/systemctl" --version
)
printf '%s\n' "$version_output" | grep -Eq '^systemd [0-9]+' || fail 'systemctl version output was not preserved'
if printf '%s\n' "$version_output" | grep -Eq '^[0-9]+$'; then
    fail 'wrapper contaminated successful stdout with a numeric status line'
fi
grep -Fq 'event=finish command=systemctl status=0' "$COMMAND_LOG" || fail 'successful wrapper status was not logged'

set +e
ARCH_EXECUTOR_COMMAND_LOG=$COMMAND_LOG \
    sh "$TMP_DIR/systemctl" is-active morimil-wrapper-contract-missing.service \
    > "$TMP_DIR/inactive.stdout" \
    2> "$TMP_DIR/inactive.stderr"
inactive_status=$?
set -e

[ "$inactive_status" -ne 0 ] || fail 'missing service probe unexpectedly returned success'
if grep -Eq '^[0-9]+$' "$TMP_DIR/inactive.stdout"; then
    fail 'wrapper contaminated failed stdout with a numeric status line'
fi
grep -Fq "event=finish command=systemctl status=$inactive_status" "$COMMAND_LOG" || fail 'failed wrapper status was not logged'

printf 'Runtime command wrapper contract tests passed.\n'
