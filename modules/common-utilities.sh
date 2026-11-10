#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Common workstation utilities.
#
# Provides baseline command-line tools that are broadly useful across
# supported workstation profiles.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "common-utilities"
}

module_name() {
    printf '%s\n' "Common Utilities"
}

module_description() {
    printf '%s\n' \
        "Baseline command-line utilities used across workstation profiles."
}

module_capabilities() {
    printf '%s\n' \
        "curl" \
        "dos2unix" \
        "nano" \
        "sed" \
        "wget" \
        "xz"
}

# Verify that the commands provided by this module are available after
# installation. Package-state verification remains handled by the execution
# framework; this check confirms the expected utilities are actually usable.
module_verify() {
    local utility
    local verification_failed=false

    local -a required_utilities=(
        "curl"
        "dos2unix"
        "nano"
        "sed"
        "wget"
        "xz"
    )

    for utility in "${required_utilities[@]}"; do
        if command_exists "$utility"; then
            continue
        fi

        printf 'Error: required common utility is unavailable: %s\n' \
            "$utility" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}
