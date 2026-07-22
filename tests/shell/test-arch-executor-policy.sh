#!/bin/sh

set -eu

case "$0" in
    */*) TEST_DIR=${0%/*} ;;
    *) TEST_DIR=. ;;
esac

ROOT_DIR=$TEST_DIR/../..

python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
check = root / "scripts" / "check-arch-executor-policy.sh"
valid = root / "config" / "nspawn" / "morimil-arch.nspawn"
limits = root / "config" / "arch-executor-resource-limits.env"


def accepted(path: Path, limits_path: Path = limits) -> bool:
    result = subprocess.run(
        ["sh", str(check), str(path), str(limits_path)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


if not accepted(valid):
    raise SystemExit("canonical Arch executor policy was rejected")

source = valid.read_text(encoding="utf-8")
cases = {
    "shared host networking": source.replace("Private=yes", "Private=no"),
    "identity UID mapping": source.replace("PrivateUsers=pick", "PrivateUsers=identity"),
    "runtime idmapped ownership": source.replace("PrivateUsersOwnership=off", "PrivateUsersOwnership=map"),
    "runtime recursive chown": source.replace("PrivateUsersOwnership=off", "PrivateUsersOwnership=chown"),
    "host journal link": source.replace("LinkJournal=no", "LinkJournal=host"),
    "host resolver import": source.replace("ResolvConf=off", "ResolvConf=bind-host"),
    "host timezone import": source.replace("Timezone=off", "Timezone=bind"),
    "capability grant": source + "\nCapability=all\n",
    "host device bind": source + "\nBind=/dev:/dev\n",
    "writable root override": source.replace("ReadOnly=yes", "ReadOnly=no"),
    "uncapped volatile state": source.replace(
        "TemporaryFileSystem=/var:mode=0755,nodev,nosuid,size=268435456,nr_inodes=65536",
        "Volatile=state",
    ),
    "larger var tmpfs": source.replace("size=268435456", "size=536870912"),
    "larger inode allowance": source.replace("nr_inodes=65536", "nr_inodes=131072"),
    "virtual ethernet": source.replace("VirtualEthernet=no", "VirtualEthernet=yes"),
}

with tempfile.TemporaryDirectory(prefix="morimil-arch-policy-") as temp:
    temp_dir = Path(temp)
    for index, (name, content) in enumerate(cases.items()):
        candidate = temp_dir / f"case-{index}.nspawn"
        candidate.write_text(content, encoding="utf-8")
        if accepted(candidate):
            raise SystemExit(f"unsafe policy was accepted: {name}")

    mismatched_limits = temp_dir / "limits.env"
    mismatched_limits.write_text(
        limits.read_text(encoding="utf-8").replace(
            "MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES=268435456",
            "MORIMIL_ARCH_EXECUTOR_VAR_SIZE_BYTES=134217728",
        ),
        encoding="utf-8",
    )
    if accepted(valid, mismatched_limits):
        raise SystemExit("policy was accepted against mismatched storage limits")

    if accepted(temp_dir / "missing.nspawn"):
        raise SystemExit("missing policy was accepted")

print("Arch executor policy contract tests passed.")
PY
