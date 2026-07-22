#!/bin/sh

set -eu

COMMAND=${0##*/}
COMMAND_LOG=${ARCH_EXECUTOR_COMMAND_LOG:-/tmp/morimil-arch-runtime-commands.log}

case "$COMMAND" in
    systemd-nspawn)
        DEADLINE=${ARCH_EXECUTOR_NSPAWN_TIMEOUT:-420}
        for argument in "$@"; do
            if [ "$argument" = '--private-users-ownership=chown' ]; then
                DEADLINE=${ARCH_EXECUTOR_OWNERSHIP_TIMEOUT:-900}
                break
            fi
        done
        REAL_COMMAND=/usr/bin/systemd-nspawn
        ;;
    systemd-run)
        DEADLINE=${ARCH_EXECUTOR_REMOTE_COMMAND_TIMEOUT:-90}
        REAL_COMMAND=/usr/bin/systemd-run
        ;;
    machinectl)
        DEADLINE=${ARCH_EXECUTOR_CONTROL_TIMEOUT:-90}
        REAL_COMMAND=/usr/bin/machinectl
        ;;
    systemctl)
        DEADLINE=${ARCH_EXECUTOR_CONTROL_TIMEOUT:-90}
        REAL_COMMAND=/usr/bin/systemctl
        ;;
    *)
        printf 'error: unsupported runtime wrapper command: %s\n' "$COMMAND" >&2
        exit 2
        ;;
esac

case "$DEADLINE" in
    *[!0-9]*|'')
        printf 'error: invalid deadline for %s: %s\n' "$COMMAND" "$DEADLINE" >&2
        exit 2
        ;;
esac
[ "$DEADLINE" -ge 10 ] || {
    printf 'error: deadline for %s must be at least 10 seconds\n' "$COMMAND" >&2
    exit 2
}

mkdir -p "${COMMAND_LOG%/*}"
{
    printf 'event=start command=%s deadline=%s pid=%s\n' "$COMMAND" "$DEADLINE" "$$"
    printf 'argv='; printf ' <%s>' "$@"; printf '\n'
} >> "$COMMAND_LOG"

set +e
/usr/bin/timeout \
    --signal=TERM \
    --kill-after=15s \
    "$DEADLINE" \
    "$REAL_COMMAND" "$@"
STATUS=$?
set -e

printf 'event=finish command=%s status=%s pid=%s\n' "$COMMAND" "$STATUS" "$$" >> "$COMMAND_LOG"
exit "$STATUS"
