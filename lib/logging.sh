#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Application logging utilities.
# This file:
# 1. Resolves the application state and log directories.
# 2. Creates a separate log file for each bootstrap session.
# 3. Provides consistent application log levels.

# Runtime logging paths.
# These values are populated by init_logging().
LWBS_STATE_DIR=""
LWBS_LOG_DIR=""
LWBS_LOG_FILE=""

# Initialize persistent logging for the current bootstrap session.
init_logging() {
    local state_root
    local timestamp

    # Prefer the XDG state directory when it has been configured by the user.
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        state_root="$XDG_STATE_HOME"

    # Fall back to the standard user-local state location.
    elif [[ -n "${HOME:-}" ]]; then
        state_root="$HOME/.local/state"

    else
        printf 'Error: unable to determine the user state directory.\n' >&2
        return 1
    fi

    LWBS_STATE_DIR="$state_root/linux-workstation-bootstrap"
    LWBS_LOG_DIR="$LWBS_STATE_DIR/logs"

    # Create the log directory if this is the first application run.
    mkdir -p -- "$LWBS_LOG_DIR"

    # Restrict access because future logs may contain system information.
    chmod 700 -- "$LWBS_STATE_DIR" "$LWBS_LOG_DIR"

    # Include the process ID to prevent collisions between simultaneous runs.
    printf -v timestamp '%(%Y%m%d-%H%M%S)T' -1
    LWBS_LOG_FILE="$LWBS_LOG_DIR/run-${timestamp}-$$.log"

    # Create the session log with user-only read/write permissions.
    touch -- "$LWBS_LOG_FILE"
    chmod 600 -- "$LWBS_LOG_FILE"
}

# Write a timestamped message to the current session log.
log_message() {
    local level="$1"
    local message="$2"
    local timestamp

    # Logging must be initialized before messages can be written.
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

# Write an informational event to the session log.
log_info() {
    log_message "INFO" "$1"
}

# Write a warning event to the session log.
log_warning() {
    log_message "WARN" "$1"
}

# Write an error event to the session log.
log_error() {
    log_message "ERROR" "$1"
}