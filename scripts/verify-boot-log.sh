#!/bin/sh

set -eu

BOOT_LOG=${1:-}

if [ -z "$BOOT_LOG" ]; then
    printf 'usage: %s BOOT_LOG\n' "$0" >&2
    exit 2
fi

if [ ! -f "$BOOT_LOG" ]; then
    printf 'error: boot log not found: %s\n' "$BOOT_LOG" >&2
    exit 1
fi

if grep -Fq -- 'MORIMIL_BOOT_PROOF_FAILED' "$BOOT_LOG"; then
    printf 'error: guest reported that multi-user.target was not active\n' >&2
    exit 1
fi

if ! grep -Fq -- 'MORIMIL_BOOT_PROOF target=multi-user.target state=active' "$BOOT_LOG"; then
    printf 'error: boot proof marker was not found in %s\n' "$BOOT_LOG" >&2
    exit 1
fi

printf 'Boot proof verified: multi-user.target was active before guest shutdown.\n'
