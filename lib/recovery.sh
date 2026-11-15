#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Interrupted-run detection and recovery state tracking.
#
# Recovery metadata records only operational identifiers required to
# understand an incomplete run. Command arguments, configuration contents,
# credentials, tokens, URLs, and other sensitive values are never persisted.
#
# Recovery does not perform rollback and does not automatically continue from
# an interrupted action. A subsequent invocation rebuilds its execution plan
# from actual system state and relies on the existing idempotency framework.
#
# shellcheck disable=SC2154

LWBS_RECOVERY_DIR=""
LWBS_RECOVERY_ACTIVE_FILE=""
LWBS_RECOVERY_LAST_FILE=""

LWBS_RECOVERY_CURRENT_RUN_ID=""
LWBS_RECOVERY_CURRENT_STATUS=""
LWBS_RECOVERY_CURRENT_PROFILE=""
LWBS_RECOVERY_CURRENT_DISTRO=""
LWBS_RECOVERY_CURRENT_STARTED_AT=""
LWBS_RECOVERY_CURRENT_UPDATED_AT=""
LWBS_RECOVERY_CURRENT_LOG_FILE=""

LWBS_RECOVERY_LAST_SUCCESS_TYPE=""
LWBS_RECOVERY_LAST_SUCCESS_MODULE=""
LWBS_RECOVERY_LAST_SUCCESS_TARGET=""
LWBS_RECOVERY_LAST_SUCCESS_AT=""

LWBS_RECOVERY_PREVIOUS_INTERRUPTED=false
LWBS_RECOVERY_PREVIOUS_RUN_ID=""
LWBS_RECOVERY_PREVIOUS_PROFILE=""
LWBS_RECOVERY_PREVIOUS_DISTRO=""
LWBS_RECOVERY_PREVIOUS_STARTED_AT=""
LWBS_RECOVERY_PREVIOUS_UPDATED_AT=""
LWBS_RECOVERY_PREVIOUS_LOG_FILE=""
LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TYPE=""
LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_MODULE=""
LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TARGET=""
LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_AT=""

recovery_timestamp() {
    local timestamp

    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    printf '%s\n' "$timestamp"
}

recovery_run_id() {
    local timestamp

    printf -v timestamp '%(%Y%m%d-%H%M%S)T' -1

    printf '%s-%s\n' \
        "$timestamp" \
        "$$"
}

initialize_recovery_state() {
    if [[ -z "${LWBS_STATE_DIR:-}" ]]; then
        printf 'Error: recovery state requires initialized application state.\n' \
            >&2
        return 1
    fi

    LWBS_RECOVERY_DIR="$LWBS_STATE_DIR/$LWBS_RECOVERY_DIRECTORY_NAME"
    LWBS_RECOVERY_ACTIVE_FILE="$LWBS_RECOVERY_DIR/$LWBS_RECOVERY_ACTIVE_FILE_NAME"
    LWBS_RECOVERY_LAST_FILE="$LWBS_RECOVERY_DIR/$LWBS_RECOVERY_LAST_FILE_NAME"

    if ! mkdir -p -- "$LWBS_RECOVERY_DIR"; then
        printf 'Error: unable to create recovery state directory.\n' >&2
        return 1
    fi

    if ! chmod "$LWBS_RECOVERY_DIR_MODE" -- "$LWBS_RECOVERY_DIR"; then
        printf 'Error: unable to secure recovery state directory.\n' >&2
        return 1
    fi

    return 0
}

recovery_write_state_map() {
    local destination="${1:-}"
    local state_name="${2:-}"
    local temporary_file

    if [[ -z "$destination" || -z "$state_name" ]]; then
        return 2
    fi

    local -n state_ref="$state_name"

    temporary_file="$destination.tmp.$$"

    {
        printf 'format_version=1\n'
        printf 'run_id=%s\n' "${state_ref[run_id]:-unknown}"
        printf 'status=%s\n' "${state_ref[status]:-unknown}"
        printf 'profile=%s\n' "${state_ref[profile]:-unknown}"
        printf 'distro=%s\n' "${state_ref[distro]:-unknown}"
        printf 'started_at=%s\n' "${state_ref[started_at]:-unknown}"
        printf 'updated_at=%s\n' "${state_ref[updated_at]:-unknown}"
        printf 'log_file=%s\n' "${state_ref[log_file]:-unknown}"
        printf 'last_success_type=%s\n' "${state_ref[last_success_type]:-}"
        printf 'last_success_module=%s\n' "${state_ref[last_success_module]:-}"
        printf 'last_success_target=%s\n' "${state_ref[last_success_target]:-}"
        printf 'last_success_at=%s\n' "${state_ref[last_success_at]:-}"
    } >"$temporary_file"

    if ! chmod "$LWBS_RECOVERY_FILE_MODE" -- "$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi

    if ! mv -f -- "$temporary_file" "$destination"; then
        rm -f -- "$temporary_file"
        return 1
    fi

    return 0
}

recovery_read_state_file() {
    local source_file="${1:-}"
    local state_name="${2:-}"
    local line
    local key
    local value

    if [[ -z "$source_file" ||
        -z "$state_name" ||
        ! -r "$source_file" ]]; then

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

        if [[ ! "$key" =~ ^[a-z_][a-z0-9_]*$ ]]; then
            return 1
        fi

        case "$key" in
            format_version | run_id | status | profile | distro | started_at | updated_at | log_file | last_success_type | last_success_module | last_success_target | last_success_at)
                state_ref["$key"]="$value"
                ;;

            *)
                return 1
                ;;
        esac
    done <"$source_file"

    if [[ "${state_ref[format_version]:-}" != "1" ||
        -z "${state_ref[status]:-}" ]]; then

        return 1
    fi

    return 0
}

recovery_write_current_state() {
    local -A state=()

    state["run_id"]="$LWBS_RECOVERY_CURRENT_RUN_ID"
    state["status"]="$LWBS_RECOVERY_CURRENT_STATUS"
    state["profile"]="$LWBS_RECOVERY_CURRENT_PROFILE"
    state["distro"]="$LWBS_RECOVERY_CURRENT_DISTRO"
    state["started_at"]="$LWBS_RECOVERY_CURRENT_STARTED_AT"
    state["updated_at"]="$LWBS_RECOVERY_CURRENT_UPDATED_AT"
    state["log_file"]="$LWBS_RECOVERY_CURRENT_LOG_FILE"
    state["last_success_type"]="$LWBS_RECOVERY_LAST_SUCCESS_TYPE"
    state["last_success_module"]="$LWBS_RECOVERY_LAST_SUCCESS_MODULE"
    state["last_success_target"]="$LWBS_RECOVERY_LAST_SUCCESS_TARGET"
    state["last_success_at"]="$LWBS_RECOVERY_LAST_SUCCESS_AT"

    recovery_write_state_map \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        state
}

recovery_begin_run() {
    local profile_id="${1:-}"
    local distro_profile="${2:-}"

    if [[ -z "$profile_id" || -z "$distro_profile" ]]; then
        printf 'Error: recovery run requires profile and distribution identifiers.\n' \
            >&2
        return 2
    fi

    if ! initialize_recovery_state; then
        return 1
    fi

    if [[ -e "$LWBS_RECOVERY_ACTIVE_FILE" ]]; then
        printf 'Error: unresolved active recovery state already exists.\n' >&2
        return 1
    fi

    LWBS_RECOVERY_CURRENT_RUN_ID="$(recovery_run_id)"
    LWBS_RECOVERY_CURRENT_STATUS="executing"
    LWBS_RECOVERY_CURRENT_PROFILE="$profile_id"
    LWBS_RECOVERY_CURRENT_DISTRO="$distro_profile"
    LWBS_RECOVERY_CURRENT_STARTED_AT="$(recovery_timestamp)"
    LWBS_RECOVERY_CURRENT_UPDATED_AT="$LWBS_RECOVERY_CURRENT_STARTED_AT"

    if [[ -n "${LWBS_LOG_FILE:-}" ]]; then
        LWBS_RECOVERY_CURRENT_LOG_FILE="$(basename -- "$LWBS_LOG_FILE")"
    else
        LWBS_RECOVERY_CURRENT_LOG_FILE=""
    fi

    LWBS_RECOVERY_LAST_SUCCESS_TYPE=""
    LWBS_RECOVERY_LAST_SUCCESS_MODULE=""
    LWBS_RECOVERY_LAST_SUCCESS_TARGET=""
    LWBS_RECOVERY_LAST_SUCCESS_AT=""

    if ! recovery_write_current_state; then
        printf 'Error: unable to create active recovery state.\n' >&2
        return 1
    fi

    log_info \
        "Recovery lifecycle started: run_id=$LWBS_RECOVERY_CURRENT_RUN_ID profile=$profile_id distro=$distro_profile"

    return 0
}

recovery_record_successful_action() {
    local action_type="${1:-}"
    local module_id="${2:-}"
    local target="${3:-}"

    if [[ "$LWBS_RECOVERY_CURRENT_STATUS" != "executing" ||
        ! -f "${LWBS_RECOVERY_ACTIVE_FILE:-}" ]]; then

        return 0
    fi

    if [[ -z "$action_type" ||
        -z "$module_id" ||
        -z "$target" ]]; then

        return 2
    fi

    LWBS_RECOVERY_LAST_SUCCESS_TYPE="$action_type"
    LWBS_RECOVERY_LAST_SUCCESS_MODULE="$module_id"
    LWBS_RECOVERY_LAST_SUCCESS_TARGET="$target"
    LWBS_RECOVERY_LAST_SUCCESS_AT="$(recovery_timestamp)"
    LWBS_RECOVERY_CURRENT_UPDATED_AT="$LWBS_RECOVERY_LAST_SUCCESS_AT"

    if ! recovery_write_current_state; then
        log_warning \
            "Unable to persist recovery checkpoint: type=$action_type module=$module_id target=$target"

        return 1
    fi

    log_info \
        "Recovery checkpoint updated: type=$action_type module=$module_id target=$target"

    return 0
}

recovery_finalize_run() {
    local final_status="${1:-}"

    case "$final_status" in
        completed | failed | interrupted) ;;
        *)
            printf 'Error: invalid recovery final status: %s\n' \
                "$final_status" >&2
            return 2
            ;;
    esac

    if [[ -z "$LWBS_RECOVERY_CURRENT_RUN_ID" ]]; then
        return 0
    fi

    LWBS_RECOVERY_CURRENT_STATUS="$final_status"
    LWBS_RECOVERY_CURRENT_UPDATED_AT="$(recovery_timestamp)"

    if ! recovery_write_current_state; then
        return 1
    fi

    if ! cp -- \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        "$LWBS_RECOVERY_LAST_FILE.tmp.$$"; then

        return 1
    fi

    if ! chmod \
        "$LWBS_RECOVERY_FILE_MODE" \
        "$LWBS_RECOVERY_LAST_FILE.tmp.$$"; then

        rm -f -- "$LWBS_RECOVERY_LAST_FILE.tmp.$$"
        return 1
    fi

    if ! mv -f -- \
        "$LWBS_RECOVERY_LAST_FILE.tmp.$$" \
        "$LWBS_RECOVERY_LAST_FILE"; then

        rm -f -- "$LWBS_RECOVERY_LAST_FILE.tmp.$$"
        return 1
    fi

    if ! rm -f -- "$LWBS_RECOVERY_ACTIVE_FILE"; then
        return 1
    fi

    log_info \
        "Recovery lifecycle finalized: run_id=$LWBS_RECOVERY_CURRENT_RUN_ID status=$final_status"

    return 0
}

recovery_load_previous_interrupted_state() {
    local state_name="${1:-}"

    local -n state_ref="$state_name"

    LWBS_RECOVERY_PREVIOUS_INTERRUPTED=true
    LWBS_RECOVERY_PREVIOUS_RUN_ID="${state_ref[run_id]:-unknown}"
    LWBS_RECOVERY_PREVIOUS_PROFILE="${state_ref[profile]:-unknown}"
    LWBS_RECOVERY_PREVIOUS_DISTRO="${state_ref[distro]:-unknown}"
    LWBS_RECOVERY_PREVIOUS_STARTED_AT="${state_ref[started_at]:-unknown}"
    LWBS_RECOVERY_PREVIOUS_UPDATED_AT="${state_ref[updated_at]:-unknown}"
    LWBS_RECOVERY_PREVIOUS_LOG_FILE="${state_ref[log_file]:-}"
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TYPE="${state_ref[last_success_type]:-}"
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_MODULE="${state_ref[last_success_module]:-}"
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TARGET="${state_ref[last_success_target]:-}"
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_AT="${state_ref[last_success_at]:-}"
}

recovery_archive_previous_state() {
    local state_name="${1:-}"

    if ! recovery_write_state_map \
        "$LWBS_RECOVERY_LAST_FILE" \
        "$state_name"; then

        return 1
    fi

    rm -f -- "$LWBS_RECOVERY_ACTIVE_FILE"
}

recovery_detect_previous_run() {
    local -A previous_state=()
    local status

    if ! initialize_recovery_state; then
        return 1
    fi

    LWBS_RECOVERY_PREVIOUS_INTERRUPTED=false

    if [[ ! -e "$LWBS_RECOVERY_ACTIVE_FILE" ]]; then
        return 0
    fi

    if ! recovery_read_state_file \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        previous_state; then

        printf '\nWarning: incomplete bootstrap recovery metadata was found but could not be read safely.\n'
        printf 'The previous run may have terminated unexpectedly.\n'
        printf 'No automatic rollback or continuation will be attempted.\n\n'

        log_warning \
            "Unreadable active recovery state detected."

        rm -f -- "$LWBS_RECOVERY_ACTIVE_FILE"

        return 0
    fi

    status="${previous_state[status]}"

    case "$status" in
        completed | failed)
            recovery_archive_previous_state previous_state
            return $?
            ;;

        interrupted) ;;

        executing | *)
            previous_state["status"]="interrupted"
            previous_state["updated_at"]="$(recovery_timestamp)"
            ;;
    esac

    if ! recovery_archive_previous_state previous_state; then
        return 1
    fi

    recovery_load_previous_interrupted_state previous_state

    log_warning \
        "Interrupted previous run detected: run_id=$LWBS_RECOVERY_PREVIOUS_RUN_ID profile=$LWBS_RECOVERY_PREVIOUS_PROFILE"

    show_previous_interrupted_run

    return 0
}

show_previous_interrupted_run() {
    printf '\nPrevious bootstrap run was incomplete\n\n'

    printf '  Run ID       : %s\n' \
        "$LWBS_RECOVERY_PREVIOUS_RUN_ID"

    printf '  Profile      : %s\n' \
        "$LWBS_RECOVERY_PREVIOUS_PROFILE"

    printf '  Distribution : %s\n' \
        "$LWBS_RECOVERY_PREVIOUS_DISTRO"

    if [[ -n "$LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TYPE" ]]; then
        printf '  Last success : %s %s' \
            "$LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TYPE" \
            "$LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TARGET"

        if [[ -n "$LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_MODULE" ]]; then
            printf ' (module: %s)' \
                "$LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_MODULE"
        fi

        printf '\n'
    else
        printf '  Last success : none recorded\n'
    fi

    if [[ -n "$LWBS_RECOVERY_PREVIOUS_LOG_FILE" ]]; then
        printf '  Previous log : %s/%s\n' \
            "$LWBS_LOG_DIR" \
            "$LWBS_RECOVERY_PREVIOUS_LOG_FILE"
    fi

    printf '\n'
    printf 'Recovery will rebuild the execution plan from current system state.\n'
    printf 'No automatic rollback or checkpoint continuation will be attempted.\n\n'
}

show_recovery_plan_notice() {
    if ! "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED"; then
        return 0
    fi

    printf 'Recovery      : previous incomplete run detected; plan rebuilt from current state\n\n'
}

show_recovery_summary() {
    if ! "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED" &&
        [[ -z "$LWBS_RECOVERY_CURRENT_STATUS" ]]; then

        return 0
    fi

    printf '\nRecovery summary\n\n'

    if "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED"; then
        printf '  Previous run : interrupted (%s)\n' \
            "$LWBS_RECOVERY_PREVIOUS_RUN_ID"
    fi

    if [[ -n "$LWBS_RECOVERY_CURRENT_STATUS" ]]; then
        printf '  Current run  : %s\n' \
            "$LWBS_RECOVERY_CURRENT_STATUS"
    fi

    printf '\n'
}

recovery_handle_signal() {
    local signal_name="${1:-}"
    local exit_code

    case "$signal_name" in
        HUP)
            exit_code=129
            ;;

        INT)
            exit_code=130
            ;;

        TERM)
            exit_code=143
            ;;

        *)
            exit_code=1
            ;;
    esac

    log_warning \
        "Bootstrap interrupted by signal: $signal_name"

    recovery_finalize_run interrupted || true

    trap - HUP INT TERM

    exit "$exit_code"
}

recovery_install_signal_handlers() {
    trap 'recovery_handle_signal HUP' HUP
    trap 'recovery_handle_signal INT' INT
    trap 'recovery_handle_signal TERM' TERM
}

recovery_clear_signal_handlers() {
    trap - HUP INT TERM
}

reset_recovery_runtime_state() {
    LWBS_RECOVERY_CURRENT_RUN_ID=""
    LWBS_RECOVERY_CURRENT_STATUS=""
    LWBS_RECOVERY_CURRENT_PROFILE=""
    LWBS_RECOVERY_CURRENT_DISTRO=""
    LWBS_RECOVERY_CURRENT_STARTED_AT=""
    LWBS_RECOVERY_CURRENT_UPDATED_AT=""
    LWBS_RECOVERY_CURRENT_LOG_FILE=""

    LWBS_RECOVERY_LAST_SUCCESS_TYPE=""
    LWBS_RECOVERY_LAST_SUCCESS_MODULE=""
    LWBS_RECOVERY_LAST_SUCCESS_TARGET=""
    LWBS_RECOVERY_LAST_SUCCESS_AT=""

    LWBS_RECOVERY_PREVIOUS_INTERRUPTED=false
    LWBS_RECOVERY_PREVIOUS_RUN_ID=""
    LWBS_RECOVERY_PREVIOUS_PROFILE=""
    LWBS_RECOVERY_PREVIOUS_DISTRO=""
    LWBS_RECOVERY_PREVIOUS_STARTED_AT=""
    LWBS_RECOVERY_PREVIOUS_UPDATED_AT=""
    LWBS_RECOVERY_PREVIOUS_LOG_FILE=""
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TYPE=""
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_MODULE=""
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_TARGET=""
    LWBS_RECOVERY_PREVIOUS_LAST_SUCCESS_AT=""
}
