#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Command execution utilities.
# Provides a common execution path so command handling, privilege escalation,
# dry-run behaviour, logging, and error propagation remain consistent.
#
# This file:
# 1. Provides a common path for executing system commands.
# 2. Provides controlled execution for commands requiring root privileges.
# 3. Enforces dry-run behaviour.
# 4. Records command execution results in the session log.
# 5. Preserves command exit codes for the calling application.

# The log currently records: -> [ Executing command: apt-get ] rather than blindly dumping every argument.
# Arguments may eventually contain tokens, credentials, URLs with parameters, or other sensitive values.
# Avoiding creating an unsafe logging primitive that would need to be repaired later.
# Package operations can explicitly log package names and other values known to be safe.
#

# Execute a command using the current bootstrap execution mode.
run_command() {
    local exit_code
    local command_name

    # A command is required.
    if (($# == 0)); then
        printf 'Error: no command was provided for execution.\n' >&2
        log_error "Command execution requested without a command."
        return 2
    fi

    command_name="$1"

    # In dry-run mode, report the intended command without executing it.
    if "$LWBS_DRY_RUN"; then
        printf '[DRY-RUN] Would execute: %s\n' "$command_name"
        log_info "Dry-run skipped command: $command_name"
        return 0
    fi

    # Record the command being started without blindly logging its arguments.
    log_info "Executing command: $command_name"

    # Execute the command exactly as provided by the caller.
    if "$@"; then
        log_info "Command completed successfully: $command_name"
        return 0
    else
        exit_code=$?

        log_error \
            "Command failed: command=$command_name exit_code=$exit_code"

        return "$exit_code"
    fi
}

# Execute a command that requires root privileges.
run_privileged_command() {
    local command_name

    # A command is required.
    if (($# == 0)); then
        printf 'Error: no privileged command was provided for execution.\n' >&2
        log_error "Privileged command execution requested without a command."
        return 2
    fi

    command_name="$1"

    # Dry-run does not require sudo because no privileged command is executed.
    if "$LWBS_DRY_RUN"; then
        printf '[DRY-RUN] Would execute with root privileges: %s\n' \
            "$command_name"

        log_info \
            "Dry-run skipped privileged command: $command_name"

        return 0
    fi

    # Commands can be executed directly when the bootstrap already has
    # effective root privileges.
    if ((EUID == 0)); then
        run_command "$@"
        return $?
    fi

    # A non-root session requires sudo for privileged system operations.
    if ! command_exists sudo; then
        printf 'Error: root privileges are required to execute: %s\n' \
            "$command_name" >&2

        printf 'Error: sudo is not available on this system.\n' >&2

        log_error \
            "Unable to execute privileged command because sudo is unavailable: $command_name"

        return 1
    fi

    # Keep privilege escalation centralized rather than implementing sudo
    # handling separately inside each distribution adapter.
    log_info "Executing privileged command: $command_name"

    # sudo executes the requested command while run_command retains the
    # common execution and exit-code handling.
    run_command sudo -- "$@"
}