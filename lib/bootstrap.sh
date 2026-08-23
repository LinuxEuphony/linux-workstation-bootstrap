#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Main application bootstrap.
# This file:
# 1. Loads the application components.
# 2. Coordinates system detection.
# 3. Determines the distribution profile to use.
# 4. Controls the main bootstrap execution flow.

# Load system detection utilities.
# shellcheck source=./detect.sh
source "$LWBS_ROOT/lib/detect.sh"

# Load terminal user interface utilities.
# shellcheck source=./ui.sh
source "$LWBS_ROOT/lib/ui.sh"

# Current development version of Linux Workstation Bootstrap.
readonly LWBS_VERSION="0.1.0-dev"

# Distribution profile selected for the current bootstrap session.
SELECTED_DISTRO_PROFILE=""

# Main application entry point.
# All command-line arguments from the executable are passed here.
bootstrap_main() {
    # Start each interactive bootstrap session with a clean terminal.
    clear_screen

    detect_system
    show_system_summary
    select_distro_profile

    printf 'Selected profile: %s\n' \
        "$(profile_name "$SELECTED_DISTRO_PROFILE")"
}

# Determine which supported distribution profile should be used.
select_distro_profile() {
    # Use the detected distribution directly when it is supported
    # and the user confirms the selection.
    if is_supported_distro "$SYSTEM_DISTRO_ID" &&
        confirm_detected_profile; then
        SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"
        return 0
    fi

    # Fall back to manual selection when the detected profile is
    # unsupported or the user chooses not to use it.
    if ! choose_distro_profile; then
        printf 'Bootstrap cancelled.\n'
        return 1
    fi
}

# Check whether a distribution currently has a supported profile.
is_supported_distro() {
    case "$1" in
        ubuntu | debian | kali)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}