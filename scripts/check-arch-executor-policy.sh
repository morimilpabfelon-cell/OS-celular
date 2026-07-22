#!/bin/sh

set -eu

CONFIG=${1:-config/nspawn/morimil-arch.nspawn}
LIMITS_CONFIG=${2:-config/arch-executor-resource-limits.env}

if [ ! -f "$CONFIG" ]; then
    printf 'error: Arch executor policy is missing: %s\n' "$CONFIG" >&2
    exit 1
fi
if [ ! -f "$LIMITS_CONFIG" ]; then
    printf 'error: Arch executor resource limits are missing: %s\n' "$LIMITS_CONFIG" >&2
    exit 1
fi

python3 - "$CONFIG" "$LIMITS_CONFIG" <<'PY'
import configparser
from pathlib import Path
import re
import sys

policy_path = Path(sys.argv[1])
limits_path = Path(sys.argv[2])

limits: dict[str, str] = {}
for number, raw_line in enumerate(limits_path.read_text(encoding="utf-8").splitlines(), 1):
    if not raw_line or raw_line.startswith("#"):
        continue
    match = re.fullmatch(r"([A-Z0-9_]+)=([0-9]+)", raw_line)
    if match is None:
        raise SystemExit(f"error: invalid resource limit line {number}: {raw_line!r}")
    key, value = match.groups()
    if key in limits:
        raise SystemExit(f"error: duplicate resource limit: {key}")
    limits[key] = value

try:
    var_size = limits["MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES"]
    var_inodes = limits["MORIMIL_ARCH_EXECUTOR_VAR_INODES"]
except KeyError as exc:
    raise SystemExit(f"error: policy validation is missing resource limit {exc.args[0]}") from exc

expected = {
    "Exec": {
        "Boot": "yes",
        "PrivateUsers": "pick",
        "NoNewPrivileges": "yes",
        "Hostname": "morimil-arch",
        "LinkJournal": "no",
        "ResolvConf": "off",
        "Timezone": "off",
    },
    "Files": {
        "ReadOnly": "yes",
        "PrivateUsersOwnership": "off",
        "TemporaryFileSystem": (
            f"/var:mode=0755,nodev,nosuid,size={var_size},nr_inodes={var_inodes}"
        ),
    },
    "Network": {
        "Private": "yes",
        "VirtualEthernet": "no",
    },
}

parser = configparser.ConfigParser(interpolation=None, strict=True)
parser.optionxform = str

try:
    with policy_path.open(encoding="utf-8") as handle:
        parser.read_file(handle)
except (OSError, UnicodeError, configparser.Error) as exc:
    raise SystemExit(f"error: invalid Arch executor policy: {exc}") from exc

actual_sections = set(parser.sections())
expected_sections = set(expected)
if actual_sections != expected_sections:
    missing = sorted(expected_sections - actual_sections)
    extra = sorted(actual_sections - expected_sections)
    raise SystemExit(
        f"error: section mismatch; missing={missing or 'none'} extra={extra or 'none'}"
    )

for section, required in expected.items():
    actual = dict(parser.items(section))
    if set(actual) != set(required):
        missing = sorted(set(required) - set(actual))
        extra = sorted(set(actual) - set(required))
        raise SystemExit(
            f"error: [{section}] key mismatch; "
            f"missing={missing or 'none'} extra={extra or 'none'}"
        )

    for key, value in required.items():
        if actual[key] != value:
            raise SystemExit(
                f"error: [{section}] {key} must equal {value}, got {actual[key]}"
            )
PY

printf 'Arch executor policy passed.\n'
printf 'This result validates configuration policy only; it does not prove that an Arch rootfs boots.\n'
