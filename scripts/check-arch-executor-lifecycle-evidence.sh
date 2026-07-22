#!/bin/sh

set -eu

EVIDENCE_DIR=${1:-build/arch-executor-lifecycle/evidence}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

value() {
    file=$1
    key=$2
    result=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file")
    [ -n "$result" ] || fail "missing $key in $file"
    printf '%s\n' "$result"
}

for path in \
    host-before.env \
    host-after.env \
    create-command.env \
    created-status.env \
    generation-1-rootfs-source.env \
    first-start-command.env \
    first-running-status.env \
    first-ready.env \
    first-uid-map.txt \
    first-root-options.txt \
    first-var-fstype.txt \
    first-network-interfaces.txt \
    first-no-new-privileges.txt \
    first-netns.env \
    first-stop-command.env \
    first-stopped-status.env \
    rebuild-command.env \
    rebuilt-status.env \
    generation-2-rootfs-source.env \
    second-start-command.env \
    second-running-status.env \
    second-ready.env \
    second-uid-map.txt \
    second-root-options.txt \
    second-var-fstype.txt \
    second-network-interfaces.txt \
    second-no-new-privileges.txt \
    second-netns.env \
    second-stop-command.env \
    destroy-command.env \
    destroyed-status.env \
    lifecycle-summary.env
do
    [ -s "$EVIDENCE_DIR/$path" ] || fail "required lifecycle evidence is missing or empty: $path"
done

for file in create-command.env first-start-command.env first-stop-command.env second-start-command.env second-stop-command.env destroy-command.env; do
    grep -Fq 'machine=morimil-arch' "$EVIDENCE_DIR/$file" || fail "$file has the wrong machine"
done

grep -Fqx 'result=created' "$EVIDENCE_DIR/create-command.env" || fail 'create did not report success'
grep -Fqx 'state=stopped' "$EVIDENCE_DIR/created-status.env" || fail 'created executor was not stopped'
grep -Fqx 'created=yes' "$EVIDENCE_DIR/created-status.env" || fail 'created executor was not complete'
grep -Fqx 'running=no' "$EVIDENCE_DIR/created-status.env" || fail 'create unexpectedly started the executor'

grep -Fqx 'result=started' "$EVIDENCE_DIR/first-start-command.env" || fail 'first start did not report success'
grep -Fqx 'state=running' "$EVIDENCE_DIR/first-running-status.env" || fail 'first runtime was not running'
grep -Fqx 'created=yes' "$EVIDENCE_DIR/first-running-status.env" || fail 'first runtime lost created state'
grep -Fqx 'running=yes' "$EVIDENCE_DIR/first-running-status.env" || fail 'first runtime status lacks running=yes'

grep -Fqx 'result=stopped' "$EVIDENCE_DIR/first-stop-command.env" || fail 'first stop did not report success'
grep -Fqx 'state=stopped' "$EVIDENCE_DIR/first-stopped-status.env" || fail 'first stop did not preserve stopped state'
grep -Fqx 'running=no' "$EVIDENCE_DIR/first-stopped-status.env" || fail 'first stop left the executor running'

grep -Fq 'result=created' "$EVIDENCE_DIR/rebuild-command.env" || fail 'rebuild did not recreate the executor'
grep -Fqx 'state=stopped' "$EVIDENCE_DIR/rebuilt-status.env" || fail 'rebuild did not leave the executor stopped'
grep -Fqx 'running=no' "$EVIDENCE_DIR/rebuilt-status.env" || fail 'rebuild unexpectedly started the executor'

grep -Fqx 'result=started' "$EVIDENCE_DIR/second-start-command.env" || fail 'second start did not report success'
grep -Fqx 'state=running' "$EVIDENCE_DIR/second-running-status.env" || fail 'second runtime was not running'
grep -Fqx 'result=stopped' "$EVIDENCE_DIR/second-stop-command.env" || fail 'second stop did not report success'
grep -Fqx 'result=destroyed' "$EVIDENCE_DIR/destroy-command.env" || fail 'destroy did not report success'
grep -Fqx 'state=absent' "$EVIDENCE_DIR/destroyed-status.env" || fail 'destroy did not remove lifecycle state'
grep -Fqx 'created=no' "$EVIDENCE_DIR/destroyed-status.env" || fail 'destroy left a created executor'
grep -Fqx 'running=no' "$EVIDENCE_DIR/destroyed-status.env" || fail 'destroy left a running executor'

GEN1_SHA=$(value "$EVIDENCE_DIR/generation-1-rootfs-source.env" MORIMIL_ROOTFS_SHA256)
GEN2_SHA=$(value "$EVIDENCE_DIR/generation-2-rootfs-source.env" MORIMIL_ROOTFS_SHA256)
[ "$GEN1_SHA" = "$GEN2_SHA" ] || fail 'rebuild used a different rootfs SHA-256'
[ "$(value "$EVIDENCE_DIR/created-status.env" rootfs_sha256)" = "$GEN1_SHA" ] || fail 'created status rootfs checksum mismatch'
[ "$(value "$EVIDENCE_DIR/rebuilt-status.env" rootfs_sha256)" = "$GEN2_SHA" ] || fail 'rebuilt status rootfs checksum mismatch'

for label in first second; do
    grep -Fqx 'pid1_comm=systemd' "$EVIDENCE_DIR/$label-ready.env" || fail "$label runtime does not use systemd as PID 1"
    grep -Fqx 'network_interfaces=lo' "$EVIDENCE_DIR/$label-ready.env" || fail "$label runtime exposes a non-loopback interface"
    [ "$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-network-interfaces.txt")" = lo ] || fail "$label runtime network listing is not loopback-only"
    [ "$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-var-fstype.txt")" = tmpfs ] || fail "$label runtime /var is not tmpfs"
    [ "$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-no-new-privileges.txt")" = 1 ] || fail "$label runtime lacks NoNewPrivileges"
    root_options=$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-root-options.txt")
    case ",$root_options," in
        *,ro,*) ;;
        *) fail "$label runtime root is not read-only" ;;
    esac
    host_uid_start=$(awk 'NR == 1 { print $2 }' "$EVIDENCE_DIR/$label-uid-map.txt")
    case "$host_uid_start" in
        ''|*[!0-9]*) fail "$label UID map is invalid" ;;
    esac
    [ "$host_uid_start" -ge 65536 ] || fail "$label UID map exposes container root too low"
    host_netns=$(value "$EVIDENCE_DIR/$label-netns.env" host)
    container_netns=$(value "$EVIDENCE_DIR/$label-netns.env" container)
    [ "$host_netns" != "$container_netns" ] || fail "$label runtime shares the host network namespace"
done

[ "$(value "$EVIDENCE_DIR/host-before.env" boot_id)" = "$(value "$EVIDENCE_DIR/host-after.env" boot_id)" ] || fail 'host boot ID changed'
[ "$(value "$EVIDENCE_DIR/host-before.env" sentinel_sha256)" = "$(value "$EVIDENCE_DIR/host-after.env" sentinel_sha256)" ] || fail 'host sentinel changed'
[ "$(value "$EVIDENCE_DIR/host-before.env" network_sha256)" = "$(value "$EVIDENCE_DIR/host-after.env" network_sha256)" ] || fail 'host network interfaces changed'

for expected in \
    host_architecture=aarch64 \
    create=yes \
    first_start=yes \
    first_stop=yes \
    rebuild=yes \
    second_start=yes \
    second_stop=yes \
    destroy=yes \
    host_unchanged=yes \
    rootfs_removed=yes \
    state_removed=yes \
    policy_removed=yes
 do
    grep -Fqx "$expected" "$EVIDENCE_DIR/lifecycle-summary.env" || fail "lifecycle summary is missing $expected"
done

printf 'Arch executor lifecycle evidence passed.\n'
