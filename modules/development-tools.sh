#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Development tools.
#
# Provides portable compiler, build, source-control, and development utilities
# used across supported workstation profiles.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "development-tools"
}

module_name() {
    printf '%s\n' "Development Tools"
}

module_description() {
    printf '%s\n' \
        "Compiler, build, source-control, and development utilities."
}

module_capabilities() {
    printf '%s\n' \
        "build-toolchain" \
        "git" \
        "cmake" \
        "pkg-config" \
        "bison" \
        "flex" \
        "swig" \
        "scons" \
        "cloc"
}

# Verify that the expected development commands are available after
# installation. Package-state verification remains the responsibility of the
# execution framework.
module_verify() {
    local command_name
    local verification_failed=false

    local -a required_commands=(
        "gcc"
        "g++"
        "make"
        "git"
        "cmake"
        "pkg-config"
        "bison"
        "flex"
        "swig"
        "scons"
        "cloc"
    )

    for command_name in "${required_commands[@]}"; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required development command is unavailable: %s\n' \
            "$command_name" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}
