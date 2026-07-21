#!/bin/sh

set -eu

CONFIG=${1:-config/nspawn/morimil-arch.nspawn}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ -f "$CONFIG" ] || fail "Arch executor policy is missing: $CONFIG"

require_header() {
    header=$1
    count=$(grep -Ec "^[[:space:]]*\\[$header\\][[:space:]]*$" "$CONFIG" || true)
    [ "$count" -eq 1 ] || fail "section [$header] must appear exactly once"
}

require_setting() {
    key=$1
    expected=$2
    count=$(grep -Ec "^[[:space:]]*$key[[:space:]]*=" "$CONFIG" || true)
    [ "$count" -eq 1 ] || fail "$key must appear exactly once"
    grep -Eq "^[[:space:]]*$key[[:space:]]*=[[:space:]]*$expected[[:space:]]*$" "$CONFIG" ||
        fail "$key must equal $expected"
}

require_header Exec
require_header Files
require_header Network

require_setting Boot yes
require_setting PrivateUsers pick
require_setting NoNewPrivileges yes
require_setting ReadOnly yes
require_setting Volatile state
require_setting Private yes
require_setting VirtualEthernet no

forbidden='Capability|AmbientCapability|Bind|BindReadOnly|Interface|MACVLAN|IPVLAN|Bridge|Zone|Port'
if grep -En "^[[:space:]]*($forbidden)[[:space:]]*=" "$CONFIG" >/dev/null; then
    grep -En "^[[:space:]]*($forbidden)[[:space:]]*=" "$CONFIG" >&2
    fail 'the baseline policy must not grant capabilities, host mounts, interfaces, bridges, zones, or ports'
fi

printf 'Arch executor policy passed.\n'
printf 'This result validates configuration policy only; it does not prove that an Arch rootfs boots.\n'
