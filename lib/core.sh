#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Core application utilities.
# This file:
# 1. Validates the runtime environment.
# 2. Provides reusable command availability checks.
# 3. Provides shared distribution profile validation.

# Validate the environment required to run Linux Workstation Bootstrap.
validate_runtime() {
    # The project relies on Bash-specific functionality and requires
    # the configured minimum Bash major version.
    if ((BASH_VERSINFO[0] < LWBS_MIN_BASH_MAJOR)); then
        printf 'Error: Bash %s or newer is required. Current version: %s\n' \
            "$LWBS_MIN_BASH_MAJOR" \
            "$BASH_VERSION" >&2

        return 1
    fi

    # Linux Workstation Bootstrap is intended to run only on Linux.
    if [[ "$(uname -s)" != "Linux" ]]; then
        printf 'Error: %s can only run on Linux.\n' \
            "$LWBS_APP_NAME" >&2

        return 1
    fi

    return 0
}

# Check whether a command is available in the current PATH.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verify that a required command is available.
require_command() {
    local command_name="$1"

    if command_exists "$command_name"; then
        return 0
    fi

    printf 'Error: required command not found: %s\n' \
        "$command_name" >&2

    return 1
}

# Check whether a distribution has an installation profile
# currently supported by the application.
is_supported_distro() {
    local distro

    for distro in "${LWBS_SUPPORTED_DISTROS[@]}"; do
        if [[ "$1" == "$distro" ]]; then
            return 0
        fi
    done

    return 1
}