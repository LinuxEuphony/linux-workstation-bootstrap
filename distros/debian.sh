#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Debian distribution adapter.
# Implements Debian package-management operations behind the shared
# distribution adapter contract.
#
# This file:
# 1. Validates the Debian package-management environment.
# 2. Refreshes the package index.
# 3. Installs one or more packages.
# 4. Routes privileged package operations through the shared execution layer.

# Validate the environment required by the Debian adapter.
distro_validate_environment() {
    # System detection must run before the adapter can validate the host.
    if [[ -z "${SYSTEM_DISTRO_FAMILY:-}" ]]; then
        printf 'Error: system detection must run before validating the Debian adapter.\n' \
            >&2

        log_error \
            "Debian adapter validation requested before system detection."

        return 1
    fi

    # Debian uses the Debian package-management family.
    if [[ "$SYSTEM_DISTRO_FAMILY" != "debian" ]]; then
        printf 'Error: the Debian profile requires a Debian-family system.\n' \
            >&2

        log_error \
            "Debian adapter rejected incompatible distro family: $SYSTEM_DISTRO_FAMILY"

        return 1
    fi

    # The detected package manager must match the adapter implementation.
    if [[ "$SYSTEM_PACKAGE_MANAGER" != "apt" ]]; then
        printf 'Error: the Debian profile requires the APT package manager.\n' \
            >&2

        log_error \
            "Debian adapter expected package_manager=apt but detected package_manager=$SYSTEM_PACKAGE_MANAGER"

        return 1
    fi

    # apt-get provides the stable command interface used for scripted
    # package-management operations.
    if ! require_command apt-get; then
        log_error "Debian adapter requires apt-get but it is unavailable."
        return 1
    fi

    log_info "Debian distribution adapter environment validated."

    return 0
}

# Refresh the Debian package index.
distro_update_package_index() {
    log_info "Refreshing Debian package index."

    run_privileged_command apt-get update
}

# Install one or more Debian packages.
distro_install_packages() {
    local -a packages=("$@")

    if ((${#packages[@]} == 0)); then
        printf 'Error: at least one package is required for installation.\n' \
            >&2

        log_error \
            "Debian package installation requested without packages."

        return 2
    fi

    # Package arguments are intentionally not written blindly to the log.
    # Module-level code can log package identifiers that it knows are safe.
    log_info \
        "Debian package installation requested: count=${#packages[@]}"

    run_privileged_command \
        apt-get install --yes "${packages[@]}"
}