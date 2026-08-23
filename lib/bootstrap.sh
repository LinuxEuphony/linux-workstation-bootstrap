#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Main application bootstrap.
# This file:
# 1. Loads the application components.
# 2. Initializes application logging.
# 3. Coordinates system detection.
# 4. Determines the distribution profile to use.
# 5. Controls the main bootstrap execution flow.

# Load application logging utilities.
# shellcheck source=./logging.sh
source "$LWBS_ROOT/lib/logging.sh"

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

    # Create a dedicated log file for this bootstrap session.
    init_logging

    # Show application and logging information before any processing begins.
    show_startup_info

    log_info "Linux Workstation Bootstrap $LWBS_VERSION started."

    # Detect the host operating system before selecting a bootstrap profile.
    detect_system

    log_info \
        "Detected system: distro=$SYSTEM_DISTRO_ID version=$SYSTEM_DISTRO_VERSION codename=$SYSTEM_DISTRO_CODENAME architecture=$SYSTEM_ARCH family=$SYSTEM_DISTRO_FAMILY package_manager=$SYSTEM_PACKAGE_MANAGER"

    show_system_summary

    # A cancelled profile selection is treated as a normal application exit.
    if ! select_distro_profile; then
        log_info "Bootstrap cancelled by user."
        show_cancellation_info
        return 0
    fi

    log_info "Selected distribution profile: $SELECTED_DISTRO_PROFILE"

    printf 'Selected profile: %s\n' \
        "$(profile_name "$SELECTED_DISTRO_PROFILE")"

    log_info "Bootstrap foundation completed."

    # Show completion information and the session log location.
    show_completion_info
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