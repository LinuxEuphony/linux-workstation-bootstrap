#!/usr/bin/env bash

# shellcheck disable=SC2178

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Concurrent bootstrap execution prevention.
#
# The lock is represented by an atomically created directory beneath the
# application state directory. Owner metadata records the process ID and the
# Linux process start time so PID reuse can be distinguished from a genuinely
# active bootstrap process.
#
# The lock does not terminate another process. A stale lock is removed only
# when the recorded owner can be shown to no longer match an active process.

LWBS_LOCK_DIR=""
LWBS_LOCK_METADATA_FILE=""

LWBS_LOCK_ACQUIRED=false
LWBS_LOCK_OWNER_PID=""
LWBS_LOCK_OWNER_START_TICKS=""

lock_timestamp() {
    local timestamp

    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    printf '%s\n' "$timestamp"
}

lock_process_start_ticks() {
    local pid="${1:-}"
    local stat_line
    local stat_fields_text

    local -a stat_fields=()

    if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
        return 1
    fi

    if [[ ! -r "/proc/$pid/stat" ]]; then
        return 1
    fi

    if IFS= read -r stat_line <"/proc/$pid/stat"; then
        :
    else
        return 1
    fi

    if [[ "$stat_line" != *") "* ]]; then
        return 1
    fi

    stat_fields_text="${stat_line#*) }"

    read -r -a stat_fields <<<"$stat_fields_text"

    if ((${#stat_fields[@]} < 20)); then
        return 1
    fi

    printf '%s\n' "${stat_fields[19]}"
}

initialize_execution_lock() {
    if ! initialize_application_state; then
        return 1
    fi

    LWBS_LOCK_DIR="$LWBS_STATE_DIR/$LWBS_LOCK_DIRECTORY_NAME"
    LWBS_LOCK_METADATA_FILE="$LWBS_LOCK_DIR/$LWBS_LOCK_METADATA_FILE_NAME"

    return 0
}

lock_write_metadata() {
    local pid="${1:-}"
    local start_ticks="${2:-}"
    local started_at="${3:-}"
    local temporary_file

    if [[ -z "$pid" ||
        -z "$start_ticks" ||
        -z "$started_at" ]]; then

        return 2
    fi

    temporary_file="$LWBS_LOCK_METADATA_FILE.tmp.$BASHPID"

    {
        printf 'format_version=1\n'
        printf 'pid=%s\n' "$pid"
        printf 'start_ticks=%s\n' "$start_ticks"
        printf 'started_at=%s\n' "$started_at"
    } >"$temporary_file"

    if ! chmod "$LWBS_LOCK_FILE_MODE" -- "$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi

    if ! mv -f -- "$temporary_file" "$LWBS_LOCK_METADATA_FILE"; then
        rm -f -- "$temporary_file"
        return 1
    fi

    return 0
}

lock_read_metadata() {
    local state_name="${1:-}"
    local line
    local key
    local value

    if [[ -z "$state_name" ||
        ! -r "$LWBS_LOCK_METADATA_FILE" ]]; then

        return 1
    fi

    local -n state_ref="$state_name"

    state_ref=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        if [[ "$line" != *=* ]]; then
            return 1
        fi

        key="${line%%=*}"
        value="${line#*=}"

        case "$key" in
            format_version | pid | start_ticks | started_at)
                state_ref["$key"]="$value"
                ;;

            *)
                return 1
                ;;
        esac
    done <"$LWBS_LOCK_METADATA_FILE"

    if [[ "${state_ref[format_version]:-}" != "1" ||
        ! "${state_ref[pid]:-}" =~ ^[1-9][0-9]*$ ||
        ! "${state_ref[start_ticks]:-}" =~ ^[0-9]+$ ]]; then

        return 1
    fi

    return 0
}

lock_wait_for_metadata() {
    local state_name="${1:-}"
    local attempt

    for attempt in 1 2 3 4 5; do
        if lock_read_metadata "$state_name"; then
            return 0
        fi

        sleep 0.05
    done

    return 1
}

lock_owner_is_active() {
    local state_name="${1:-}"
    local active_start_ticks

    local -n state_ref="$state_name"

    if ! kill -0 "${state_ref[pid]}" >/dev/null 2>&1; then
        return 1
    fi

    if active_start_ticks="$(
        lock_process_start_ticks \
            "${state_ref[pid]}"
    )"; then
        :
    else
        return 1
    fi

    [[ "$active_start_ticks" == "${state_ref[start_ticks]}" ]]
}

lock_remove_stale_directory() {
    local stale_path

    stale_path="${LWBS_LOCK_DIR}.stale.$BASHPID"

    rm -rf -- "$stale_path"

    if mv -- "$LWBS_LOCK_DIR" "$stale_path" 2>/dev/null; then
        rm -rf -- "$stale_path"
        return 0
    fi

    return 1
}

acquire_execution_lock() {
    local attempt
    local current_pid
    local current_start_ticks
    local started_at

    local -A owner_state=()

    if "$LWBS_LOCK_ACQUIRED"; then
        return 0
    fi

    if ! initialize_execution_lock; then
        return 1
    fi

    # Capture BASHPID before entering command substitution. BASHPID changes
    # inside command-substitution subshells, so using it directly inside the
    # substitution would associate the caller PID with another process's
    # start time.
    current_pid="$BASHPID"

    if current_start_ticks="$(
        lock_process_start_ticks \
            "$current_pid"
    )"; then
        :
    else
        printf 'Error: unable to determine bootstrap process identity.\n' >&2
        return 1
    fi

    started_at="$(lock_timestamp)"

    for attempt in 1 2 3; do
        if mkdir -- "$LWBS_LOCK_DIR" 2>/dev/null; then
            if ! chmod "$LWBS_LOCK_DIR_MODE" -- "$LWBS_LOCK_DIR"; then
                rm -rf -- "$LWBS_LOCK_DIR"
                return 1
            fi

            if ! lock_write_metadata \
                "$current_pid" \
                "$current_start_ticks" \
                "$started_at"; then

                rm -rf -- "$LWBS_LOCK_DIR"

                printf 'Error: unable to persist bootstrap execution lock metadata.\n' \
                    >&2

                return 1
            fi

            LWBS_LOCK_ACQUIRED=true
            LWBS_LOCK_OWNER_PID="$current_pid"
            LWBS_LOCK_OWNER_START_TICKS="$current_start_ticks"

            return 0
        fi

        owner_state=()

        if ! lock_wait_for_metadata owner_state; then
            printf 'Error: bootstrap execution lock exists but its owner metadata cannot be verified.\n' \
                >&2

            printf 'Refusing to remove an unverifiable lock automatically: %s\n' \
                "$LWBS_LOCK_DIR" >&2

            return 1
        fi

        if lock_owner_is_active owner_state; then
            printf 'Error: another Linux Workstation Bootstrap process is already running.\n' \
                >&2

            printf '  PID       : %s\n' \
                "${owner_state[pid]}" >&2

            printf '  Started   : %s\n' \
                "${owner_state[started_at]:-unknown}" >&2

            return 1
        fi

        if lock_remove_stale_directory; then
            continue
        fi
    done

    printf 'Error: unable to acquire bootstrap execution lock.\n' >&2

    return 1
}

release_execution_lock() {
    local current_pid
    local current_start_ticks

    local -A owner_state=()

    if ! "$LWBS_LOCK_ACQUIRED"; then
        return 0
    fi

    if [[ ! -d "$LWBS_LOCK_DIR" ]]; then
        LWBS_LOCK_ACQUIRED=false
        LWBS_LOCK_OWNER_PID=""
        LWBS_LOCK_OWNER_START_TICKS=""

        return 0
    fi

    if ! lock_read_metadata owner_state; then
        printf 'Warning: bootstrap lock metadata is unavailable; lock was not removed.\n' \
            >&2

        return 1
    fi

    current_pid="$BASHPID"

    if current_start_ticks="$(
        lock_process_start_ticks \
            "$current_pid"
    )"; then
        :
    else
        return 1
    fi

    if [[ "${owner_state[pid]}" != "$current_pid" ||
        "${owner_state[start_ticks]}" != "$current_start_ticks" ]]; then

        printf 'Warning: bootstrap execution lock belongs to another process; lock was not removed.\n' \
            >&2

        return 1
    fi

    if ! rm -rf -- "$LWBS_LOCK_DIR"; then
        return 1
    fi

    LWBS_LOCK_ACQUIRED=false
    LWBS_LOCK_OWNER_PID=""
    LWBS_LOCK_OWNER_START_TICKS=""

    return 0
}

lock_install_exit_handler() {
    trap 'release_execution_lock || true' EXIT
}

reset_execution_lock_state() {
    LWBS_LOCK_DIR=""
    LWBS_LOCK_METADATA_FILE=""
    LWBS_LOCK_ACQUIRED=false
    LWBS_LOCK_OWNER_PID=""
    LWBS_LOCK_OWNER_START_TICKS=""
}