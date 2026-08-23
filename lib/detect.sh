#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# System detection utilities.
# This file:
# 1. Reads Linux distribution information from /etc/os-release.
# 2. Determines the distribution family.
# 3. Detects and normalizes the system architecture.
# 4. Identifies the expected package manager for the distribution family.

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
    local os_release="${LWBS_OS_RELEASE:-/etc/os-release}"
    local -a os_info=()

    # /etc/os-release is the standard source of Linux distribution metadata.
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

    # Derive additional system information used by later bootstrap modules.
    SYSTEM_DISTRO_FAMILY="$(resolve_distro_family)"
    SYSTEM_ARCH="$(detect_architecture)"
    SYSTEM_PACKAGE_MANAGER="$(resolve_package_manager)"
}

# Determine the broader distribution family.
resolve_distro_family() {
    case "$SYSTEM_DISTRO_ID" in
        ubuntu | debian | kali)
            printf 'debian\n'
            return
            ;;
        fedora | rhel | rocky | almalinux | centos)
            printf 'rpm\n'
            return
            ;;
        arch | manjaro | endeavouros)
            printf 'arch\n'
            return
            ;;
        opensuse* | sles)
            printf 'suse\n'
            return
            ;;
    esac

    # Fall back to ID_LIKE for distributions derived from another distro.
    if [[ " $SYSTEM_DISTRO_LIKE " == *" debian "* ]]; then
        printf 'debian\n'
    elif [[ " $SYSTEM_DISTRO_LIKE " == *" fedora "* ]] ||
        [[ " $SYSTEM_DISTRO_LIKE " == *" rhel "* ]]; then
        printf 'rpm\n'
    elif [[ " $SYSTEM_DISTRO_LIKE " == *" arch "* ]]; then
        printf 'arch\n'
    elif [[ " $SYSTEM_DISTRO_LIKE " == *" suse "* ]]; then
        printf 'suse\n'
    else
        printf 'unknown\n'
    fi
}

# Determine the package manager normally associated with the distro family.
resolve_package_manager() {
    case "$SYSTEM_DISTRO_FAMILY" in
        debian)
            printf 'apt\n'
            ;;
        rpm)
            printf 'dnf\n'
            ;;
        arch)
            printf 'pacman\n'
            ;;
        suse)
            printf 'zypper\n'
            ;;
        *)
            printf 'unknown\n'
            ;;
    esac
}

# Detect the machine architecture and normalize common Linux architecture names.
detect_architecture() {
    local architecture

    architecture="$(uname -m)"

    case "$architecture" in
        x86_64)
            printf 'amd64\n'
            ;;
        aarch64 | arm64)
            printf 'arm64\n'
            ;;
        armv7l | armv7*)
            printf 'armhf\n'
            ;;
        i386 | i486 | i586 | i686)
            printf 'i386\n'
            ;;
        *)
            # Preserve unknown architectures rather than incorrectly mapping them.
            printf '%s\n' "$architecture"
            ;;
    esac
}
