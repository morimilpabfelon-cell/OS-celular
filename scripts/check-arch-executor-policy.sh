#!/bin/sh

set -eu

CONFIG=${1:-config/nspawn/morimil-arch.nspawn}

if [ ! -f "$CONFIG" ]; then
    printf 'error: Arch executor policy is missing: %s\n' "$CONFIG" >&2
    exit 1
fi

python3 - "$CONFIG" <<'PY'
import configparser
from pathlib import Path
import sys

path = Path(sys.argv[1])
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
        "Volatile": "state",
        "PrivateUsersOwnership": "chown",
    },
    "Network": {
        "Private": "yes",
        "VirtualEthernet": "no",
    },
}

parser = configparser.ConfigParser(interpolation=None, strict=True)
parser.optionxform = str

try:
    with path.open(encoding="utf-8") as handle:
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
