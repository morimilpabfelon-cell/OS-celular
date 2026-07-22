#!/bin/sh

set -eu

EVIDENCE_DIR=${1:-build/arch-executor-runtime/evidence}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for path in \
    "$EVIDENCE_DIR/runtime-summary.env" \
    "$EVIDENCE_DIR/validation-status.env" \
    "$EVIDENCE_DIR/host-before.env" \
    "$EVIDENCE_DIR/host-after.env" \
    "$EVIDENCE_DIR/clean-proof.env" \
    "$EVIDENCE_DIR/rebuild-proof.env" \
    "$EVIDENCE_DIR/clean-uid-map.txt" \
    "$EVIDENCE_DIR/rebuild-uid-map.txt" \
    "$EVIDENCE_DIR/clean-root-options.txt" \
    "$EVIDENCE_DIR/rebuild-root-options.txt" \
    "$EVIDENCE_DIR/clean-var-fstype.txt" \
    "$EVIDENCE_DIR/rebuild-var-fstype.txt" \
    "$EVIDENCE_DIR/clean-network-interfaces.txt" \
    "$EVIDENCE_DIR/rebuild-network-interfaces.txt" \
    "$EVIDENCE_DIR/generation-1-rootfs-source.env" \
    "$EVIDENCE_DIR/generation-2-rootfs-source.env" \
    "$EVIDENCE_DIR/generation-1-uid-shift.txt" \
    "$EVIDENCE_DIR/generation-2-uid-shift.txt" \
    "$EVIDENCE_DIR/ownership-shift-generation-1.log" \
    "$EVIDENCE_DIR/ownership-shift-generation-2.log" \
    "$EVIDENCE_DIR/cleanup-status.env"
do
    [ -f "$path" ] || fail "required runtime evidence is missing: $path"
done

if find "$EVIDENCE_DIR" -maxdepth 1 -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.img' -o -name '*.raw' \) | grep -q .; then
    fail 'runtime evidence must not retain rootfs archives or images'
fi

get_value() {
    file=$1
    key=$2
    value=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file")
    [ -n "$value" ] || fail "missing runtime evidence value: $key in $file"
    printf '%s\n' "$value"
}

SUMMARY=$EVIDENCE_DIR/runtime-summary.env
STATUS=$EVIDENCE_DIR/validation-status.env
CLEANUP=$EVIDENCE_DIR/cleanup-status.env

[ "$(get_value "$STATUS" MORIMIL_ARCH_EXECUTOR_RUNTIME_VALIDATED)" = yes ] || fail 'runtime validation status must be yes'
[ "$(get_value "$SUMMARY" host_architecture)" = aarch64 ] || fail 'runtime validation must execute natively on AArch64'
[ "$(get_value "$SUMMARY" clean_boot)" = yes ] || fail 'clean boot was not validated'
[ "$(get_value "$SUMMARY" clean_shutdown)" = yes ] || fail 'clean shutdown was not validated'
[ "$(get_value "$SUMMARY" forced_failure)" = yes ] || fail 'forced failure was not validated'
[ "$(get_value "$SUMMARY" host_survived_failure)" = yes ] || fail 'host survival was not validated'
[ "$(get_value "$SUMMARY" reconstruction)" = yes ] || fail 'rootfs reconstruction was not validated'
[ "$(get_value "$SUMMARY" rebuild_boot)" = yes ] || fail 'rebuilt rootfs boot was not validated'
[ "$(get_value "$SUMMARY" private_users)" = yes ] || fail 'private user namespace was not validated'
[ "$(get_value "$SUMMARY" private_network)" = yes ] || fail 'private network namespace was not validated'
[ "$(get_value "$SUMMARY" root_read_only)" = yes ] || fail 'read-only root was not validated'
[ "$(get_value "$SUMMARY" volatile_state)" = yes ] || fail 'volatile state was not validated'
[ "$(get_value "$SUMMARY" no_new_privileges)" = yes ] || fail 'NoNewPrivileges was not validated'

FAILURE_EXIT=$(get_value "$SUMMARY" forced_failure_exit)
case "$FAILURE_EXIT" in
    *[!0-9]*|'') fail 'forced failure exit must be numeric' ;;
esac
[ "$FAILURE_EXIT" -ne 0 ] || fail 'forced failure must produce a non-zero nspawn exit'

for label in clean rebuild; do
    case "$label" in
        clean) generation=1 ;;
        rebuild) generation=2 ;;
    esac

    proof=$EVIDENCE_DIR/$label-proof.env
    [ "$(get_value "$proof" pid1_comm)" = systemd ] || fail "$label boot did not use systemd as PID 1"
    [ "$(get_value "$proof" network_interfaces)" = lo ] || fail "$label boot exposed a non-loopback interface"

    interfaces=$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-network-interfaces.txt")
    [ "$interfaces" = lo ] || fail "$label runtime interface evidence must contain only lo"

    root_options=$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-root-options.txt")
    case ",$root_options," in
        *,ro,*) ;;
        *) fail "$label root mount is not read-only" ;;
    esac

    var_fstype=$(tr -d '\r\n' < "$EVIDENCE_DIR/$label-var-fstype.txt")
    [ "$var_fstype" = tmpfs ] || fail "$label /var is not volatile tmpfs"

    host_uid_start=$(awk 'NR == 1 { print $2 }' "$EVIDENCE_DIR/$label-uid-map.txt")
    case "$host_uid_start" in
        *[!0-9]*|'') fail "$label UID map is invalid" ;;
    esac

    prepared_shift=$(tr -d '\r\n' < "$EVIDENCE_DIR/generation-$generation-uid-shift.txt")
    case "$prepared_shift" in
        *[!0-9]*|'') fail "generation $generation prepared UID shift is invalid" ;;
    esac
    [ "$prepared_shift" -ge 65536 ] || fail "generation $generation prepared UID shift is unexpectedly small"
    [ $((prepared_shift % 65536)) -eq 0 ] || fail "generation $generation prepared UID shift is not aligned to 65536"
    [ "$host_uid_start" = "$prepared_shift" ] || fail "$label UID map does not match the prepared ownership shift"
done

[ "$(get_value "$EVIDENCE_DIR/clean-proof.env" generation)" = 1 ] || fail 'clean proof generation mismatch'
[ "$(get_value "$EVIDENCE_DIR/rebuild-proof.env" generation)" = 2 ] || fail 'rebuild proof generation mismatch'

BEFORE_BOOT_ID=$(get_value "$EVIDENCE_DIR/host-before.env" boot_id)
AFTER_BOOT_ID=$(get_value "$EVIDENCE_DIR/host-after.env" boot_id)
[ "$BEFORE_BOOT_ID" = "$AFTER_BOOT_ID" ] || fail 'host boot ID changed during runtime validation'

BEFORE_SENTINEL=$(get_value "$EVIDENCE_DIR/host-before.env" sentinel_sha256)
AFTER_SENTINEL=$(get_value "$EVIDENCE_DIR/host-after.env" sentinel_sha256)
[ "$BEFORE_SENTINEL" = "$AFTER_SENTINEL" ] || fail 'host sentinel changed during runtime validation'

GEN1_SHA=$(get_value "$EVIDENCE_DIR/generation-1-rootfs-source.env" MORIMIL_ROOTFS_SHA256)
GEN2_SHA=$(get_value "$EVIDENCE_DIR/generation-2-rootfs-source.env" MORIMIL_ROOTFS_SHA256)
[ "$GEN1_SHA" = "$GEN2_SHA" ] || fail 'reconstructed rootfs checksum differs from generation 1'

[ "$(get_value "$CLEANUP" rootfs_removed)" = yes ] || fail 'rootfs cleanup was not validated'
[ "$(get_value "$CLEANUP" state_removed)" = yes ] || fail 'state cleanup was not validated'
[ "$(get_value "$CLEANUP" machine_unregistered)" = yes ] || fail 'machine cleanup was not validated'
[ "$(get_value "$CLEANUP" trusted_policy_removed)" = yes ] || fail 'trusted policy cleanup was not validated'

printf 'Arch executor runtime evidence passed.\n'
printf 'rootfs_sha256=%s\n' "$GEN1_SHA"
printf 'forced_failure_exit=%s\n' "$FAILURE_EXIT"
