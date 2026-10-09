#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Ubuntu distribution adapter.
# Implements Ubuntu package-management operations behind the shared
# distribution adapter contract.
#
# This file:
# 1. Validates the Ubuntu package-management environment.
# 2. Detects whether repository packages are already installed.
# 3. Refreshes the package index.
# 4. Installs repository packages.
# 5. Installs local distribution package files.
# 6. Routes privileged package operations through the shared execution layer.

distro_validate_environment() {
    if [[ -z "${SYSTEM_DISTRO_FAMILY:-}" ]]; then
        printf 'Error: system detection must run before validating the Ubuntu adapter.\n' \
            >&2

        log_error \
            "Ubuntu adapter validation requested before system detection."

        return 1
    fi

    if [[ "$SYSTEM_DISTRO_FAMILY" != "debian" ]]; then
        printf 'Error: the Ubuntu profile requires a Debian-family system.\n' \
            >&2

        log_error \
            "Ubuntu adapter rejected incompatible distro family: $SYSTEM_DISTRO_FAMILY"

        return 1
    fi

    if [[ "$SYSTEM_PACKAGE_MANAGER" != "apt" ]]; then
        printf 'Error: the Ubuntu profile requires the APT package manager.\n' \
            >&2

        log_error \
            "Ubuntu adapter expected package_manager=apt but detected package_manager=$SYSTEM_PACKAGE_MANAGER"

        return 1
    fi

    if ! require_command apt-get; then
        log_error "Ubuntu adapter requires apt-get but it is unavailable."
        return 1
    fi

    if ! require_command dpkg-query; then
        log_error "Ubuntu adapter requires dpkg-query but it is unavailable."
        return 1
    fi

    log_info "Ubuntu distribution adapter environment validated."

    return 0
}

# Report whether a package is installed.
#
# Output:
#   installed
#   absent
#
# A successfully determined absent package still returns zero. Non-zero
# return values are reserved for state-check failures.
distro_package_state() {
    local package="${1:-}"
    local package_status
    local exit_code

    if [[ -z "$package" ]]; then
        printf 'Error: no Ubuntu package was provided for state checking.\n' >&2
        return 2
    fi

    if [[ ! "$package" =~ ^[A-Za-z0-9][A-Za-z0-9.+:_-]*$ ]]; then
        printf 'Error: invalid Ubuntu package identifier: %s\n' \
            "$package" >&2
        return 2
    fi

    if package_status="$(
        dpkg-query \
            -W \
            -f='${db:Status-Status}' \
            -- "$package" \
            2>/dev/null
    )"; then
        if [[ "$package_status" == "installed" ]]; then
            printf '%s\n' "installed"
        else
            printf '%s\n' "absent"
        fi

        return 0
    else
        exit_code=$?
    fi

    # dpkg-query returns 1 when the requested package is unknown or absent.
    if ((exit_code == 1)); then
        printf '%s\n' "absent"
        return 0
    fi

    printf 'Error: unable to determine Ubuntu package state: %s\n' \
        "$package" >&2

    log_error \
        "Ubuntu package state check failed: package=$package exit_code=$exit_code"

    return "$exit_code"
}

distro_update_package_index() {
    log_info "Refreshing Ubuntu package index."

    run_privileged_command apt-get update
}

distro_install_packages() {
    local -a packages=("$@")

    if ((${#packages[@]} == 0)); then
        printf 'Error: at least one package is required for installation.\n' \
            >&2

        log_error \
            "Ubuntu package installation requested without packages."

        return 2
    fi

    log_info \
        "Ubuntu package installation requested: count=${#packages[@]}"

    run_privileged_command \
        apt-get install --yes "${packages[@]}"
}

distro_install_local_package() {
    local package_file="${1:-}"

    if [[ -z "$package_file" ]]; then
        printf 'Error: no local Ubuntu package file was provided.\n' >&2
        log_error "Ubuntu local package installation requested without a file."
        return 2
    fi

    if [[ "$package_file" != /* ]]; then
        printf 'Error: local Ubuntu package path must be absolute.\n' >&2
        return 2
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$package_file" ]]; then
        printf 'Error: local Ubuntu package file not found: %s\n' \
            "$package_file" >&2
        return 1
    fi

    log_info "Ubuntu local package installation requested."

    run_privileged_command \
        apt-get install --yes "$package_file"
}