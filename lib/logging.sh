#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Application state and logging utilities.
#
# Application state initialization is separated from session-log creation so
# the bootstrap can establish its execution lock before creating mutable
# per-run logging state.

LWBS_STATE_DIR=""
LWBS_LOG_DIR=""
LWBS_LOG_FILE=""

resolve_application_state_root() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s\n' "$XDG_STATE_HOME"
        return 0
    fi

    if [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "$HOME/.local/state"
        return 0
    fi

    printf 'Error: unable to determine the user state directory.\n' >&2
    return 1
}

initialize_application_state() {
    local state_root

    if state_root="$(resolve_application_state_root)"; then
        :
    else
        return $?
    fi

    LWBS_STATE_DIR="$state_root/$LWBS_APP_SLUG"

    if ! mkdir -p -- "$LWBS_STATE_DIR"; then
        printf 'Error: unable to create application state directory.\n' >&2
        return 1
    fi

    if ! chmod "$LWBS_STATE_DIR_MODE" -- "$LWBS_STATE_DIR"; then
        printf 'Error: unable to secure application state directory.\n' >&2
        return 1
    fi

    return 0
}

init_logging() {
    local timestamp

    if ! initialize_application_state; then
        return 1
    fi

    LWBS_LOG_DIR="$LWBS_STATE_DIR/$LWBS_LOG_DIRECTORY_NAME"

    if ! mkdir -p -- "$LWBS_LOG_DIR"; then
        printf 'Error: unable to create application log directory.\n' >&2
        return 1
    fi

    if ! chmod "$LWBS_LOG_DIR_MODE" -- "$LWBS_LOG_DIR"; then
        printf 'Error: unable to secure application log directory.\n' >&2
        return 1
    fi

    printf -v timestamp '%(%Y%m%d-%H%M%S)T' -1

    LWBS_LOG_FILE="$LWBS_LOG_DIR/${LWBS_LOG_FILE_PREFIX}-${timestamp}-$$.log"

    if ! touch -- "$LWBS_LOG_FILE"; then
        printf 'Error: unable to create session log file.\n' >&2
        return 1
    fi

    if ! chmod "$LWBS_LOG_FILE_MODE" -- "$LWBS_LOG_FILE"; then
        printf 'Error: unable to secure session log file.\n' >&2
        return 1
    fi

    return 0
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp

    if [[ -z "$LWBS_LOG_FILE" ]]; then
        printf 'Error: logging has not been initialized.\n' >&2
        return 1
    fi

    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1

    printf '%s [%s] %s\n' \
        "$timestamp" \
        "$level" \
        "$message" >>"$LWBS_LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_warning() {
    log_message "WARN" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}
