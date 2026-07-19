#!/bin/sh

set -eu

case "$0" in
    */*) SCRIPT_DIR=${0%/*} ;;
    *) SCRIPT_DIR=. ;;
esac

cd "$SCRIPT_DIR/.." || exit 1
SKIP_SHELLCHECK=${SKIP_SHELLCHECK:-0}

case "$SKIP_SHELLCHECK" in
    0|1) ;;
    *)
        printf 'error: SKIP_SHELLCHECK must be 0 or 1\n' >&2
        exit 1
        ;;
esac

for path in \
    .github/workflows/validate.yml \
    README.md \
    CONTRIBUTING.md \
    docs/ARCHITECTURE.md \
    docs/ROADMAP.md \
    docs/BUILDING.md \
    docs/VALIDATION.md \
    docs/adr/0001-debian-host-arch-executor.md \
    docs/adr/0002-qemu-arm64-validation-image.md \
    scripts/build-qemu-arm64.sh \
    scripts/ci-build-arm64.sh \
    scripts/configure-validation-image.sh \
    scripts/run-qemu-arm64.sh \
    scripts/verify-boot-log.sh \
    scripts/check-repository.sh \
    tests/shell/test-scripts.sh \
    tests/shell/test-boot-proof.sh
do
    if [ ! -f "$path" ]; then
        printf 'error: required file is missing: %s\n' "$path" >&2
        exit 1
    fi
done

for script in scripts/*.sh tests/shell/*.sh; do
    if [ ! -f "$script" ]; then
        continue
    fi

    if ! sh -n "$script"; then
        printf 'error: shell syntax check failed: %s\n' "$script" >&2
        exit 1
    fi
done

if [ "$SKIP_SHELLCHECK" = 0 ]; then
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck -s sh scripts/*.sh tests/shell/*.sh
    else
        printf 'warning: shellcheck is not installed; only sh -n was executed\n' >&2
    fi
fi

if git ls-files -- '*.raw' '*.qcow2' '*.img' '*.log' '*.sha256' '*.metadata' | grep -q .; then
    git ls-files -- '*.raw' '*.qcow2' '*.img' '*.log' '*.sha256' '*.metadata' >&2
    printf 'error: generated artifacts must not be tracked\n' >&2
    exit 1
fi

git diff --check

if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    git diff --check HEAD^ HEAD
else
    git show --check --root --oneline --no-renames HEAD >/dev/null
fi

printf 'Repository validation passed.\n'
printf 'This result does not prove image construction or successful boot.\n'
