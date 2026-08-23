#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Main application bootstrap.
# This file:
# 1. Loads application configuration and components.
# 2. Initializes application logging.
# 3. Validates the runtime environment.
# 4. Coordinates system detection.
# 5. Determines the distribution profile to use.
# 6. Controls the main bootstrap execution flow.

# Load default application configuration.
# shellcheck source=../config/defaults.sh
source "$LWBS_ROOT/config/defaults.sh"

# Load application logging utilities.
# shellcheck source=./logging.sh
source "$LWBS_ROOT/lib/logging.sh"

# Load core application utilities.
# shellcheck source=./core.sh
source "$LWBS_ROOT/lib/core.sh"

# Load system detection utilities.
# shellcheck source=./detect.sh
source "$LWBS_ROOT/lib/detect.sh"

# Load terminal user interface utilities.
# shellcheck source=./ui.sh
source "$LWBS_ROOT/lib/ui.sh"

# Distribution profile selected for the current bootstrap session.
SELECTED_DISTRO_PROFILE=""

# Main application entry point.
# All command-line arguments from the executable are passed here.
bootstrap_main() {
    # Start each interactive bootstrap session with a clean terminal.
    clear_screen

    # Create a dedicated log file before bootstrap processing begins.
    init_logging

    # Show application and logging information immediately.
    show_startup_info

    log_info "$LWBS_APP_NAME $LWBS_VERSION started."

    # Validate the environment before performing system operations.
    if ! validate_runtime; then
        log_error "Runtime validation failed."
        show_failure_info
        return 1
    fi

    # Detect the host operating system and architecture.
    if ! detect_system; then
        log_error "System detection failed."
        show_failure_info
        return 1
    fi

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
    # Use the detected distribution when it is supported and confirmed.
    if is_supported_distro "$SYSTEM_DISTRO_ID" &&
        confirm_detected_profile; then
        SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"
        return 0
    fi

    # Fall back to manual profile selection.
    if ! choose_distro_profile; then
        return 1
    fi

    return 0
}