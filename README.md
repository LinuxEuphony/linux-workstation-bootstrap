#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Distribution adapter utilities.
# Provides one controlled place to load the selected distro implementation
# and verify that it satisfies the adapter contract.
#
# This file:
# 1. Loads the adapter for the selected distribution profile.
# 2. Validates the distribution adapter interface.
# 3. Tracks the adapter loaded for the current bootstrap session.
# 4. Prevents unsupported or incomplete adapters from being used.

# Distribution adapter loaded for the current bootstrap session.
DISTRO_ADAPTER_PROFILE=""
DISTRO_ADAPTER_PATH=""

# Load the adapter associated with a supported distribution profile.
load_distro_adapter() {
local profile="${1:-}"
local adapter_path

    # A distribution profile must be selected before an adapter can be loaded.
    if [[ -z "$profile" ]]; then
        printf 'Error: no distribution profile was provided.\n' >&2
        log_error "Distribution adapter load requested without a profile."
        return 2
    fi

    # Only configured supported profiles may load distribution adapters.
    if ! is_supported_distro "$profile"; then
        printf 'Error: unsupported distribution profile: %s\n' \
            "$profile" >&2

        log_error \
            "Distribution adapter requested for unsupported profile: $profile"

        return 1
    fi

    adapter_path="$LWBS_ROOT/distros/$profile.sh"

    # A supported profile must have a corresponding readable adapter.
    if [[ ! -r "$adapter_path" ]]; then
        printf 'Error: distribution adapter not found: %s\n' \
            "$adapter_path" >&2

        log_error \
            "Distribution adapter file not found: profile=$profile path=$adapter_path"

        return 1
    fi

    # Remove any previously loaded contract functions before sourcing another
    # adapter so validation cannot succeed using stale functions.
    reset_distro_adapter_contract

    log_info "Loading distribution adapter: $profile"

    # shellcheck disable=SC1090
    if ! source "$adapter_path"; then
        printf 'Error: failed to load distribution adapter: %s\n' \
            "$profile" >&2

        log_error \
            "Distribution adapter source failed: profile=$profile path=$adapter_path"

        reset_distro_adapter_contract
        return 1
    fi

    # Reject adapters that do not implement the required interface.
    if ! validate_distro_adapter; then
        log_error \
            "Distribution adapter validation failed: profile=$profile"

        reset_distro_adapter_contract
        return 1
    fi

    DISTRO_ADAPTER_PROFILE="$profile"
    DISTRO_ADAPTER_PATH="$adapter_path"

    log_info "Distribution adapter loaded: $profile"

    return 0
}

# Validate the interface required from every distribution adapter.
validate_distro_adapter() {
local required_function
local -a required_functions=(
"distro_validate_environment"
"distro_update_package_index"
"distro_install_packages"
)

    for required_function in "${required_functions[@]}"; do
        if ! declare -F "$required_function" >/dev/null 2>&1; then
            printf 'Error: distribution adapter is missing required function: %s\n' \
                "$required_function" >&2

            return 1
        fi
    done

    return 0
}

# Remove functions belonging to the distribution adapter contract.
reset_distro_adapter_contract() {
unset -f \
distro_validate_environment \
distro_update_package_index \
distro_install_packages \
2>/dev/null || true

    DISTRO_ADAPTER_PROFILE=""
    DISTRO_ADAPTER_PATH=""
}