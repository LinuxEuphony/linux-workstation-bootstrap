#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# System detection utilities.
# This file:
# 1. Reads Linux distribution information from os-release.
# 2. Determines the distribution family.
# 3. Detects and normalizes the system architecture.
# 4. Determines the expected package manager.

# Detected operating system information.
# These values are populated by detect_system().
SYSTEM_DISTRO_ID=""
SYSTEM_DISTRO_NAME=""
SYSTEM_DISTRO_VERSION=""
SYSTEM_DISTRO_CODENAME=""
SYSTEM_DISTRO_LIKE=""
SYSTEM_DISTRO_FAMILY=""
SYSTEM_ARCH=""
SYSTEM_PACKAGE_MANAGER=""

# Detect the current Linux distribution and system architecture.
detect_system() {
    local os_release="${LWBS_OS_RELEASE_OVERRIDE:-$LWBS_OS_RELEASE_PATH}"
    local -a os_info=()

    # os-release is the standard source of Linux distribution metadata.
    if [[ ! -r "$os_release" ]]; then
        printf 'Error: unable to read operating system information from %s\n' \
            "$os_release" >&2

        return 1
    fi

    # Read os-release in a subshell so variables such as ID and VERSION_ID
    # do not leak into the main application environment.
    mapfile -t os_info < <(
        (
            # os-release fields may be missing, so disable nounset locally.
            set +u

            # shellcheck disable=SC1090
            source "$os_release"

            printf '%s\n' \
                "${ID:-}" \
                "${PRETTY_NAME:-}" \
                "${VERSION_ID:-}" \
                "${VERSION_CODENAME:-}" \
                "${ID_LIKE:-}"
        )
    )

    # Store the detected distribution information.
    SYSTEM_DISTRO_ID="${os_info[0]:-}"
    SYSTEM_DISTRO_NAME="${os_info[1]:-}"
    SYSTEM_DISTRO_VERSION="${os_info[2]:-}"
    SYSTEM_DISTRO_CODENAME="${os_info[3]:-}"
    SYSTEM_DISTRO_LIKE="${os_info[4]:-}"

    # Normalize identifiers to lowercase for reliable comparisons.
    SYSTEM_DISTRO_ID="${SYSTEM_DISTRO_ID,,}"
    SYSTEM_DISTRO_LIKE="${SYSTEM_DISTRO_LIKE,,}"

    # Derive additional system information from the configured mappings.
    SYSTEM_DISTRO_FAMILY="$(resolve_distro_family)"
    SYSTEM_ARCH="$(detect_architecture)"
    SYSTEM_PACKAGE_MANAGER="$(resolve_package_manager)"
}

# Determine the distribution family using the configured mappings.
resolve_distro_family() {
    local family
    local like_id
    local -a like_ids=()

    # Prefer an exact distribution mapping.
    family="${LWBS_DISTRO_FAMILIES[$SYSTEM_DISTRO_ID]:-}"

    if [[ -n "$family" ]]; then
        printf '%s\n' "$family"
        return 0
    fi

    # Fall back to ID_LIKE for derived distributions.
    read -r -a like_ids <<<"$SYSTEM_DISTRO_LIKE"

    for like_id in "${like_ids[@]}"; do
        family="${LWBS_DISTRO_FAMILIES[$like_id]:-}"

        if [[ -n "$family" ]]; then
            printf '%s\n' "$family"
            return 0
        fi
    done

    printf 'unknown\n'
}

# Determine the package manager associated with the detected distro family.
resolve_package_manager() {
    printf '%s\n' \
        "${LWBS_FAMILY_PACKAGE_MANAGERS[$SYSTEM_DISTRO_FAMILY]:-unknown}"
}

# Detect the machine architecture and normalize known architecture names.
detect_architecture() {
    local architecture

    # LWBS_ARCH_OVERRIDE is primarily useful for testing detection behavior.
    architecture="${LWBS_ARCH_OVERRIDE:-$(uname -m)}"

    printf '%s\n' \
        "${LWBS_ARCH_ALIASES[$architecture]:-$architecture}"
}