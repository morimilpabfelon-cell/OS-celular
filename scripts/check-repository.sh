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
    config/arch-rootfs-release.env \
    config/keys/archlinuxarm-build-system.asc \
    config/nspawn/morimil-arch.nspawn \
    docs/ARCHITECTURE.md \
    docs/ROADMAP.md \
    docs/BUILDING.md \
    docs/ARCH_EXECUTOR.md \
    docs/ARCH_ROOTFS_BOOTSTRAP.md \
    docs/VALIDATION.md \
    docs/adr/0001-debian-host-arch-executor.md \
    docs/adr/0002-qemu-arm64-validation-image.md \
    docs/adr/0003-arch-executor-isolation.md \
    docs/adr/0004-authenticated-arch-rootfs-bootstrap.md \
    docs/adr/0005-pinned-arch-rootfs-release.md \
    docs/adr/0006-arch-executor-lifecycle.md \
    scripts/bootstrap-arch-rootfs.sh \
    scripts/build-qemu-arm64.sh \
    scripts/check-arch-executor-lifecycle-evidence.sh \
    scripts/check-arch-executor-policy.sh \
    scripts/check-arch-executor-runtime-evidence.sh \
    scripts/check-arch-rootfs-pin.sh \
    scripts/check-arch-rootfs-release-evidence.sh \
    scripts/ci-bootstrap-arch-rootfs.sh \
    scripts/ci-build-arm64.sh \
    scripts/ci-inspect-ext4.sh \
    scripts/ci-runtime-command-wrapper.sh \
    scripts/ci-validate-arch-executor-lifecycle.sh \
    scripts/ci-validate-arch-executor-runtime.sh \
    scripts/configure-validation-image.sh \
    scripts/fingerprint-qemu-image.sh \
    scripts/inspect-arch-rootfs-release.sh \
    scripts/inspect-ext4-root.sh \
    scripts/manifest-ext4-tree.py \
    scripts/morimil-arch-executor.sh \
    scripts/normalize-qemu-image.sh \
    scripts/prepare-arch-executor-rootfs.sh \
    scripts/run-qemu-arm64.sh \
    scripts/validate-rootfs-archive.py \
    scripts/verify-boot-log.sh \
    scripts/check-repository.sh \
    tests/python/test_manifest_ext4_tree.py \
    tests/python/test_validate_rootfs_archive.py \
    tests/shell/test-scripts.sh \
    tests/shell/test-arch-executor-lifecycle-evidence.sh \
    tests/shell/test-arch-executor-lifecycle.sh \
    tests/shell/test-arch-executor-policy.sh \
    tests/shell/test-arch-executor-runtime-evidence.sh \
    tests/shell/test-arch-rootfs-bootstrap.sh \
    tests/shell/test-arch-rootfs-pin.sh \
    tests/shell/test-arch-rootfs-release-evidence.sh \
    tests/shell/test-boot-proof.sh \
    tests/shell/test-ext4-inspection.sh \
    tests/shell/test-image-configuration.sh \
    tests/shell/test-image-fingerprints.sh \
    tests/shell/test-image-normalization.sh \
    tests/shell/test-runtime-command-wrapper.sh
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

if ! command -v python3 >/dev/null 2>&1; then
    printf 'error: python3 is required for repository validation\n' >&2
    exit 1
fi

python3 - <<'PY'
from pathlib import Path

paths = sorted(Path("scripts").glob("*.py"))
paths.extend(sorted(Path("tests/python").glob("test_*.py")))
if not paths:
    raise SystemExit("no Python sources found")

for path in paths:
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

if [ "$SKIP_SHELLCHECK" = 0 ]; then
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck -s sh scripts/*.sh tests/shell/*.sh
    else
        printf 'warning: shellcheck is not installed; only sh -n was executed\n' >&2
    fi
fi

if git ls-files -- \
    '*.raw' \
    '*.qcow2' \
    '*.img' \
    '*.log' \
    '*.jsonl' \
    '*.sha256' \
    '*.metadata' \
    '*.identifiers' | grep -q .
then
    git ls-files -- \
        '*.raw' \
        '*.qcow2' \
        '*.img' \
        '*.log' \
        '*.jsonl' \
        '*.sha256' \
        '*.metadata' \
        '*.identifiers' >&2
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
