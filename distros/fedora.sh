#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Fedora distribution adapter.
#
# Implements Fedora package-management operations behind the shared
# distribution adapter contract.
#
# This file:
# 1. Validates the Fedora RPM and DNF package-management environment.
# 2. Detects whether repository packages are already installed.
# 3. Refreshes DNF repository metadata.
# 4. Installs repository packages.
# 5. Installs local RPM package files.
# 6. Routes privileged package operations through the shared execution layer.
#
# Fedora-specific package names remain in config/packages/fedora.sh rather
# than in this adapter or shared workstation modules.

distro_validate_environment() {
    if [[ -z "${SYSTEM_DISTRO_FAMILY:-}" ]]; then
        printf 'Error: system detection must run before validating the Fedora adapter.\n' \
            >&2

        log_error \
            "Fedora adapter validation requested before system detection."

        return 1
    fi

    if [[ "$SYSTEM_DISTRO_FAMILY" != "rpm" ]]; then
        printf 'Error: the Fedora profile requires an RPM-family system.\n' \
            >&2

        log_error \
            "Fedora adapter rejected incompatible distro family: $SYSTEM_DISTRO_FAMILY"

        return 1
    fi

    if [[ "$SYSTEM_PACKAGE_MANAGER" != "dnf" ]]; then
        printf 'Error: the Fedora profile requires the DNF package manager.\n' \
            >&2

        log_error \
            "Fedora adapter expected package_manager=dnf but detected package_manager=$SYSTEM_PACKAGE_MANAGER"

        return 1
    fi

    if ! require_command dnf; then
        log_error "Fedora adapter requires dnf but it is unavailable."
        return 1
    fi

    if ! require_command rpm; then
        log_error "Fedora adapter requires rpm but it is unavailable."
        return 1
    fi

    log_info "Fedora distribution adapter environment validated."

    return 0
}

# Report whether an RPM package is installed.
#
# Output:
#   installed
#   absent
#
# A successfully determined absent package still returns zero. Non-zero
# return values are reserved for package-state query failures.
distro_package_state() {
    local package="${1:-}"
    local exit_code

    if [[ -z "$package" ]]; then
        printf 'Error: no Fedora package was provided for state checking.\n' >&2
        return 2
    fi

    if [[ ! "$package" =~ ^[A-Za-z0-9][A-Za-z0-9.+:_-]*$ ]]; then
        printf 'Error: invalid Fedora package identifier: %s\n' \
            "$package" >&2

        return 2
    fi

    if rpm \
        -q \
        --quiet \
        "$package" \
        >/dev/null 2>&1; then

        printf '%s\n' "installed"
        return 0
    else
        exit_code=$?
    fi

    # rpm returns 1 when the requested package is not installed.
    if ((exit_code == 1)); then
        printf '%s\n' "absent"
        return 0
    fi

    printf 'Error: unable to determine Fedora package state: %s\n' \
        "$package" >&2

    log_error \
        "Fedora package state check failed: package=$package exit_code=$exit_code"

    return "$exit_code"
}

distro_update_package_index() {
    log_info "Refreshing Fedora repository metadata."

    run_privileged_command \
        dnf makecache --refresh
}

distro_install_packages() {
    local -a packages=("$@")

    if ((${#packages[@]} == 0)); then
        printf 'Error: at least one package is required for installation.\n' \
            >&2

        log_error \
            "Fedora package installation requested without packages."

        return 2
    fi

    log_info \
        "Fedora package installation requested: count=${#packages[@]}"

    run_privileged_command \
        dnf install --assumeyes "${packages[@]}"
}

distro_install_local_package() {
    local package_file="${1:-}"

    if [[ -z "$package_file" ]]; then
        printf 'Error: no local Fedora package file was provided.\n' >&2

        log_error \
            "Fedora local package installation requested without a file."

        return 2
    fi

    if [[ "$package_file" != /* ]]; then
        printf 'Error: local Fedora package path must be absolute.\n' >&2
        return 2
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$package_file" ]]; then
        printf 'Error: local Fedora package file not found: %s\n' \
            "$package_file" >&2

        return 1
    fi

    log_info "Fedora local package installation requested."

    run_privileged_command \
        dnf install --assumeyes "$package_file"
}
