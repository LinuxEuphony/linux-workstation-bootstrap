#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Package capability resolution utilities.
# Provides the translation layer between portable workstation capability
# identifiers and distro-specific package names.
#
# This file:
# 1. Loads package capability mappings for the selected distribution profile.
# 2. Validates capability identifiers and mapped package names.
# 3. Resolves one capability into one or more distro-specific packages.
# 4. Resolves and deduplicates multiple capability requirements.
# 5. Keeps distro-specific package names outside shared module definitions.

# Capability mapping loaded for the current distribution profile.
LWBS_CAPABILITY_PROFILE=""
LWBS_CAPABILITY_MAP_PATH=""

# Capability-to-package mappings supplied by the selected distro mapping file.
declare -A LWBS_CAPABILITY_PACKAGES=()

# Load package capability mappings for a supported distribution profile.
load_capability_map() {
    local profile="${1:-}"
    local mapping_directory
    local mapping_path

    if [[ -z "$profile" ]]; then
        printf 'Error: no distribution profile was provided for capability mapping.\n' \
            >&2

        log_error \
            "Capability map load requested without a distribution profile."

        return 2
    fi

    if ! is_supported_distro "$profile"; then
        printf 'Error: unsupported distribution profile for capability mapping: %s\n' \
            "$profile" >&2

        log_error \
            "Capability map requested for unsupported profile: $profile"

        return 1
    fi

    mapping_directory="${LWBS_CAPABILITY_MAPS_DIR_OVERRIDE:-$LWBS_ROOT/config/packages}"
    mapping_path="$mapping_directory/$profile.sh"

    if [[ ! -r "$mapping_path" ]]; then
        printf 'Error: capability mapping not found: %s\n' \
            "$mapping_path" >&2

        log_error \
            "Capability mapping file not found: profile=$profile path=$mapping_path"

        return 1
    fi

    # Remove mappings belonging to any previously loaded distro profile.
    reset_capability_map

    log_info "Loading capability mapping: $profile"

    # shellcheck disable=SC1090
    if ! source "$mapping_path"; then
        printf 'Error: failed to load capability mapping: %s\n' \
            "$profile" >&2

        log_error \
            "Capability mapping source failed: profile=$profile path=$mapping_path"

        reset_capability_map
        return 1
    fi

    if ! validate_capability_map; then
        log_error \
            "Capability mapping validation failed: profile=$profile"

        reset_capability_map
        return 1
    fi

    LWBS_CAPABILITY_PROFILE="$profile"
    LWBS_CAPABILITY_MAP_PATH="$mapping_path"

    log_info \
        "Capability mapping loaded: profile=$profile capabilities=${#LWBS_CAPABILITY_PACKAGES[@]}"

    return 0
}

# Validate all capabilities and packages in the currently loaded mapping.
validate_capability_map() {
    local capability
    local package
    local package_count
    local package_output

    if ((${#LWBS_CAPABILITY_PACKAGES[@]} == 0)); then
        printf 'Error: capability mapping does not define any capabilities.\n' \
            >&2

        return 1
    fi

    for capability in "${!LWBS_CAPABILITY_PACKAGES[@]}"; do
        if [[ ! "$capability" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
            printf 'Error: invalid capability identifier in mapping: %s\n' \
                "$capability" >&2

            return 1
        fi

        package_output="${LWBS_CAPABILITY_PACKAGES[$capability]}"
        package_count=0

        while IFS= read -r package; do
            if [[ -z "$package" ]]; then
                continue
            fi

            # Package names are data passed to the distro adapter and must
            # never be interpreted as arbitrary command-line options.
            if [[ ! "$package" =~ ^[A-Za-z0-9][A-Za-z0-9.+:_-]*$ ]]; then
                printf 'Error: invalid package mapping for capability %s: %s\n' \
                    "$capability" \
                    "$package" >&2

                return 1
            fi

            ((package_count += 1))
        done <<<"$package_output"

        if ((package_count == 0)); then
            printf 'Error: capability does not map to any packages: %s\n' \
                "$capability" >&2

            return 1
        fi
    done

    return 0
}

# Resolve one capability into the package names required by the loaded profile.
resolve_capability() {
    local capability="${1:-}"

    if [[ -z "$capability" ]]; then
        printf 'Error: no capability was provided for resolution.\n' >&2
        log_error "Capability resolution requested without a capability ID."
        return 2
    fi

    if [[ ! "$capability" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        printf 'Error: invalid capability identifier: %s\n' \
            "$capability" >&2

        log_error \
            "Invalid capability identifier requested: $capability"

        return 2
    fi

    if [[ -z "$LWBS_CAPABILITY_PROFILE" ]]; then
        printf 'Error: no capability mapping is currently loaded.\n' >&2

        log_error \
            "Capability resolution requested without a loaded mapping: $capability"

        return 1
    fi

    if [[ -z "${LWBS_CAPABILITY_PACKAGES[$capability]+defined}" ]]; then
        printf 'Error: capability "%s" is not supported by distribution profile "%s".\n' \
            "$capability" \
            "$LWBS_CAPABILITY_PROFILE" >&2

        log_error \
            "Capability mapping missing: profile=$LWBS_CAPABILITY_PROFILE capability=$capability"

        return 1
    fi

    log_info \
        "Resolved capability: profile=$LWBS_CAPABILITY_PROFILE capability=$capability"

    printf '%s\n' "${LWBS_CAPABILITY_PACKAGES[$capability]}"
}

# Resolve multiple capabilities into a deduplicated package array.
#
# Usage:
#   local -a packages=()
#   resolve_capabilities packages curl wget xz
resolve_capabilities() {
    local result_name="${1:-}"
    local capability
    local package
    local package_output
    local exit_code

    if [[ -z "$result_name" ]]; then
        printf 'Error: no output array was provided for capability resolution.\n' \
            >&2

        log_error \
            "Capability resolution requested without an output array."

        return 2
    fi

    # Namerefs accept variable names, not arbitrary expressions.
    if [[ ! "$result_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'Error: invalid output array name for capability resolution: %s\n' \
            "$result_name" >&2

        return 2
    fi

    shift

    # The nameref deliberately uses a different local identifier from the
    # caller-provided array name to avoid circular Bash nameref resolution.
    local -n output_array_ref="$result_name"
    local -A seen_packages=()

    output_array_ref=()

    for capability in "$@"; do
        if package_output="$(resolve_capability "$capability")"; then
            :
        else
            exit_code=$?
            return "$exit_code"
        fi

        while IFS= read -r package; do
            if [[ -z "$package" ]]; then
                continue
            fi

            if [[ -n "${seen_packages[$package]+defined}" ]]; then
                continue
            fi

            seen_packages["$package"]=1
            output_array_ref+=("$package")
        done <<<"$package_output"
    done

    return 0
}

# Remove the currently loaded capability mapping.
reset_capability_map() {
    LWBS_CAPABILITY_PROFILE=""
    LWBS_CAPABILITY_MAP_PATH=""
    LWBS_CAPABILITY_PACKAGES=()
}