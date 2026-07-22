#!/bin/sh

set -eu

COMMAND=${0##*/}
COMMAND_LOG=${ARCH_EXECUTOR_COMMAND_LOG:-/tmp/morimil-arch-runtime-commands.log}
RUN_STATUS=

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 2
}

validate_deadline() {
    name=$1
    value=$2
    case "$value" in
        *[!0-9]*|'') fail "invalid deadline for $name: $value" ;;
    esac
    [ "$value" -ge 10 ] || fail "deadline for $name must be at least 10 seconds"
}

log_start() {
    deadline=$1
    shift
    mkdir -p "${COMMAND_LOG%/*}"
    {
        printf 'event=start command=%s deadline=%s pid=%s\n' "$COMMAND" "$deadline" "$$"
        printf 'argv='; printf ' <%s>' "$@"; printf '\n'
    } >> "$COMMAND_LOG"
}

log_finish() {
    status=$1
    printf 'event=finish command=%s status=%s pid=%s\n' "$COMMAND" "$status" "$$" >> "$COMMAND_LOG"
}

run_bounded() {
    deadline=$1
    shift

    set +e
    /usr/bin/timeout \
        --signal=TERM \
        --kill-after=15s \
        "$deadline" \
        "$@"
    RUN_STATUS=$?
    set -e

    return 0
}

machine_leader() {
    deadline=$1
    machine=$2

    set +e
    leader=$(
        /usr/bin/timeout \
            --signal=TERM \
            --kill-after=15s \
            "$deadline" \
            /usr/bin/machinectl show "$machine" -p Leader --value
    )
    leader_status=$?
    set -e

    if [ "$leader_status" -ne 0 ]; then
        RUN_STATUS=$leader_status
        return 0
    fi

    case "$leader" in
        *[!0-9]*|'')
            RUN_STATUS=1
            return 0
            ;;
    esac
    [ -r "/proc/$leader/status" ] || {
        RUN_STATUS=1
        return 0
    }

    MACHINE_LEADER=$leader
    RUN_STATUS=0
}

run_in_namespaces() {
    deadline=$1
    machine=$2
    shift 2

    machine_leader "$deadline" "$machine"
    [ "$RUN_STATUS" -eq 0 ] || return 0
    [ -x /usr/bin/nsenter ] || fail 'nsenter is required for namespace-local runtime inspection'

    run_bounded "$deadline" \
        /usr/bin/nsenter \
        --target "$MACHINE_LEADER" \
        --user \
        --mount \
        --uts \
        --ipc \
        --net \
        --pid \
        --root="/proc/$MACHINE_LEADER/root" \
        --wd="/proc/$MACHINE_LEADER/root" \
        -- "$@"
}

configure_runtime_rootfs() {
    rootfs=$1
    [ -d "$rootfs" ] || fail "runtime rootfs is missing: $rootfs"

    unit_dir=$rootfs/etc/systemd/system
    target_wants=$unit_dir/morimil-executor.target.wants
    mkdir -p "$target_wants"

    cat > "$unit_dir/morimil-executor.target" <<'EOF_TARGET'
[Unit]
Description=Morimil isolated Arch executor target
Requires=basic.target morimil-runtime-proof.service
After=basic.target morimil-runtime-proof.service
AllowIsolate=yes
EOF_TARGET
    chmod 0644 "$unit_dir/morimil-executor.target"

    [ -f "$unit_dir/morimil-runtime-proof.service" ] || fail 'runtime proof service is missing before ownership preparation'
    chmod 0644 "$unit_dir/morimil-runtime-proof.service"
    ln -sfn ../morimil-runtime-proof.service "$target_wants/morimil-runtime-proof.service"
    ln -sfn morimil-executor.target "$unit_dir/default.target"

    for unit in \
        archlinux-keyring-wkd-sync.timer \
        systemd-networkd.service \
        systemd-networkd.socket \
        systemd-networkd-persistent-storage.service \
        systemd-networkd-resolve-hook.socket \
        systemd-networkd-varlink-metrics.socket \
        systemd-networkd-varlink.socket \
        systemd-resolved.service \
        systemd-resolved-monitor.socket \
        systemd-resolved-varlink.socket
    do
        rm -f "$unit_dir/$unit"
        ln -s /dev/null "$unit_dir/$unit"
    done

    printf '6d6f72696d696c617263686578656375\n' > "$rootfs/etc/machine-id"
    chmod 0644 "$rootfs/etc/machine-id"
    printf 'morimil-arch\n' > "$rootfs/etc/hostname"
    chmod 0644 "$rootfs/etc/hostname"
}

case "$COMMAND" in
    systemd-nspawn)
        deadline=${ARCH_EXECUTOR_NSPAWN_TIMEOUT:-420}
        ownership_prepare=0
        rootfs=
        for argument in "$@"; do
            case "$argument" in
                --private-users-ownership=chown)
                    ownership_prepare=1
                    deadline=${ARCH_EXECUTOR_OWNERSHIP_TIMEOUT:-900}
                    ;;
                --directory=*) rootfs=${argument#--directory=} ;;
            esac
        done
        validate_deadline "$COMMAND" "$deadline"
        log_start "$deadline" "$@"

        if [ "$ownership_prepare" -eq 1 ]; then
            [ -n "$rootfs" ] || fail 'ownership preparation did not provide a rootfs directory'
            configure_runtime_rootfs "$rootfs"
        fi

        run_bounded "$deadline" /usr/bin/systemd-nspawn "$@"
        status=$RUN_STATUS
        log_finish "$status"
        exit "$status"
        ;;

    systemd-run)
        deadline=${ARCH_EXECUTOR_REMOTE_COMMAND_TIMEOUT:-90}
        validate_deadline "$COMMAND" "$deadline"
        log_start "$deadline" "$@"

        machine=
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --machine=*) machine=${1#--machine=} ; shift ;;
                --quiet|--wait|--pipe) shift ;;
                --) shift; break ;;
                *) break ;;
            esac
        done
        [ -n "$machine" ] || fail 'systemd-run wrapper requires --machine='
        [ "$#" -gt 0 ] || fail 'systemd-run wrapper requires a guest command'

        run_in_namespaces "$deadline" "$machine" "$@"
        status=$RUN_STATUS
        log_finish "$status"
        exit "$status"
        ;;

    systemctl)
        deadline=${ARCH_EXECUTOR_CONTROL_TIMEOUT:-90}
        validate_deadline "$COMMAND" "$deadline"
        log_start "$deadline" "$@"

        case "${1:-}" in
            --machine=*)
                machine=${1#--machine=}
                shift
                [ "${1:-}" = is-active ] || fail 'only is-active is allowed through the machine systemctl wrapper'
                shift
                quiet=
                if [ "${1:-}" = --quiet ]; then
                    quiet=--quiet
                    shift
                fi
                target=${1:-}
                [ "$target" = multi-user.target ] || fail "unexpected machine target probe: $target"

                if [ -n "$quiet" ]; then
                    run_in_namespaces "$deadline" "$machine" /usr/bin/systemctl is-active --quiet morimil-executor.target
                else
                    run_in_namespaces "$deadline" "$machine" /usr/bin/systemctl is-active morimil-executor.target
                fi
                status=$RUN_STATUS
                ;;
            *)
                run_bounded "$deadline" /usr/bin/systemctl "$@"
                status=$RUN_STATUS
                ;;
        esac

        log_finish "$status"
        exit "$status"
        ;;

    machinectl)
        deadline=${ARCH_EXECUTOR_CONTROL_TIMEOUT:-90}
        validate_deadline "$COMMAND" "$deadline"
        log_start "$deadline" "$@"
        run_bounded "$deadline" /usr/bin/machinectl "$@"
        status=$RUN_STATUS
        log_finish "$status"
        exit "$status"
        ;;

    *) fail "unsupported runtime wrapper command: $COMMAND" ;;
esac
