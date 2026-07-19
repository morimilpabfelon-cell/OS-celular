#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

required_files='
.github/workflows/validate.yml
README.md
CONTRIBUTING.md
docs/ARCHITECTURE.md
docs/ROADMAP.md
docs/VALIDATION.md
docs/adr/0001-debian-host-arch-executor.md
scripts/check-repository.sh
'

printf '%s\n' "$required_files" |
while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -f "$path" ] || fail "required file is missing: $path"
done

find scripts -type f -name '*.sh' -print |
while IFS= read -r script; do
    sh -n "$script" || fail "shell syntax check failed: $script"
done

if command -v shellcheck >/dev/null 2>&1; then
    find scripts -type f -name '*.sh' -print |
    while IFS= read -r script; do
        shellcheck -s sh "$script" || fail "ShellCheck failed: $script"
    done
else
    printf 'warning: shellcheck is not installed; only sh -n was executed\n' >&2
fi

tracked_artifacts=$(git ls-files '*.raw' '*.qcow2' '*.img' '*.log' '*.sha256' '*.metadata')
[ -z "$tracked_artifacts" ] || {
    printf '%s\n' "$tracked_artifacts" >&2
    fail "generated artifacts must not be tracked"
}

git diff --check
git show --check --oneline --no-renames HEAD >/dev/null

printf 'Repository validation passed.\n'
printf 'This result does not prove image construction or successful boot.\n'
