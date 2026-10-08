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
# 2. Refreshes the package index.
# 3. Installs one or more packages.
# 4. Routes privileged package operations through the shared execution layer.

# Validate the environment required by the Ubuntu adapter.
distro_validate_environment() {
    # System detection must run before the adapter can validate the host.
    if [[ -z "${SYSTEM_DISTRO_FAMILY:-}" ]]; then
        printf 'Error: system detection must run before validating the Ubuntu adapter.\n' \
            >&2

        log_error \
            "Ubuntu adapter validation requested before system detection."

        return 1
    fi

    # Ubuntu uses the Debian package-management family.
    if [[ "$SYSTEM_DISTRO_FAMILY" != "debian" ]]; then
        printf 'Error: the Ubuntu profile requires a Debian-family system.\n' \
            >&2

        log_error \
            "Ubuntu adapter rejected incompatible distro family: $SYSTEM_DISTRO_FAMILY"

        return 1
    fi

    # The detected package manager must match the adapter implementation.
    if [[ "$SYSTEM_PACKAGE_MANAGER" != "apt" ]]; then
        printf 'Error: the Ubuntu profile requires the APT package manager.\n' \
            >&2

        log_error \
            "Ubuntu adapter expected package_manager=apt but detected package_manager=$SYSTEM_PACKAGE_MANAGER"

        return 1
    fi

    # apt-get is preferred over apt for scripted package operations.
    if ! require_command apt-get; then
        log_error "Ubuntu adapter requires apt-get but it is unavailable."
        return 1
    fi

    log_info "Ubuntu distribution adapter environment validated."

    return 0
}

# Refresh the Ubuntu package index.
distro_update_package_index() {
    log_info "Refreshing Ubuntu package index."

    run_privileged_command apt-get update
}

# Install one or more Ubuntu packages.
distro_install_packages() {
    local -a packages=("$@")

    if ((${#packages[@]} == 0)); then
        printf 'Error: at least one package is required for installation.\n' \
            >&2

        log_error \
            "Ubuntu package installation requested without packages."

        return 2
    fi

    # Package arguments are intentionally not written blindly to the log.
    # Module-level code can log package identifiers that it knows are safe.
    log_info \
        "Ubuntu package installation requested: count=${#packages[@]}"

    run_privileged_command \
        apt-get install --yes "${packages[@]}"
}