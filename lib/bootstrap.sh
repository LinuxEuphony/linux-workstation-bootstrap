#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Main application bootstrap.
# Coordinates the shared bootstrap layers without embedding distribution-
# specific installation logic in the application entry flow.
#
# This file:
# 1. Loads application configuration and shared components.
# 2. Processes command-line arguments.
# 3. Initializes application logging.
# 4. Validates the runtime environment.
# 5. Coordinates system detection.
# 6. Determines the distribution profile to use.
# 7. Loads and validates the selected distribution adapter.
# 8. Loads package capability mappings for the selected distribution.
# 9. Exposes the workstation module framework.
# 10. Exposes the workstation profile framework.
# 11. Controls the main bootstrap execution flow.

# Load default application configuration.
# shellcheck source=../config/defaults.sh
source "$LWBS_ROOT/config/defaults.sh"

# Load command-line argument handling.
# shellcheck source=./arguments.sh
source "$LWBS_ROOT/lib/arguments.sh"

# Load application logging utilities.
# shellcheck source=./logging.sh
source "$LWBS_ROOT/lib/logging.sh"

# Load core application utilities.
# shellcheck source=./core.sh
source "$LWBS_ROOT/lib/core.sh"

# Load command execution utilities.
# shellcheck source=./execution.sh
source "$LWBS_ROOT/lib/execution.sh"

# Load distribution adapter utilities.
# shellcheck source=./distro.sh
source "$LWBS_ROOT/lib/distro.sh"

# Load package capability resolution utilities.
# shellcheck source=./capability.sh
source "$LWBS_ROOT/lib/capability.sh"

# Load workstation module utilities.
# shellcheck source=./module.sh
source "$LWBS_ROOT/lib/module.sh"

# Load workstation profile utilities.
# shellcheck source=./profile.sh
source "$LWBS_ROOT/lib/profile.sh"

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
    # Start every interactive invocation with a clean terminal.
    clear_screen

    # Parse command-line arguments before starting the bootstrap workflow.
    if ! parse_arguments "$@"; then
        printf '\nUse --help to view supported options.\n' >&2
        return 2
    fi

    # Informational actions do not require logging or system detection.
    case "$LWBS_CLI_ACTION" in
        help)
            show_help
            return 0
            ;;
        version)
            show_version
            return 0
            ;;
    esac

    # Create a dedicated log file before bootstrap processing begins.
    init_logging

    # Show application and logging information immediately.
    show_startup_info

    log_info "$LWBS_APP_NAME $LWBS_VERSION started."

    # Record the selected execution mode.
    if "$LWBS_DRY_RUN"; then
        log_info "Dry-run mode enabled."
    fi

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

    # Determine which distribution profile should control this session.
    if ! select_distro_profile; then
        log_info "Bootstrap cancelled by user."
        show_cancellation_info
        return 0
    fi

    log_info "Selected distribution profile: $SELECTED_DISTRO_PROFILE"

    printf 'Selected profile: %s\n' \
        "$(profile_name "$SELECTED_DISTRO_PROFILE")"

    # Make profile overrides explicit when they differ from the detected host.
    if [[ "$SELECTED_DISTRO_PROFILE" != "$SYSTEM_DISTRO_ID" ]]; then
        printf 'Profile override: detected %s, selected %s\n' \
            "$SYSTEM_DISTRO_ID" \
            "$SELECTED_DISTRO_PROFILE"

        log_warning \
            "Distribution profile override: detected=$SYSTEM_DISTRO_ID selected=$SELECTED_DISTRO_PROFILE"
    fi

    # Load the implementation associated with the selected distro profile.
    if ! load_distro_adapter "$SELECTED_DISTRO_PROFILE"; then
        log_error \
            "Unable to load distribution adapter: $SELECTED_DISTRO_PROFILE"

        show_failure_info
        return 1
    fi

    # Verify that the selected adapter can operate on the detected system.
    if ! distro_validate_environment; then
        log_error \
            "Distribution adapter environment validation failed: $SELECTED_DISTRO_PROFILE"

        show_failure_info
        return 1
    fi

    log_info \
        "Distribution adapter ready: $DISTRO_ADAPTER_PROFILE"

    # Load package mappings independently from the distro adapter so shared
    # modules can express capabilities without embedding package names.
    if ! load_capability_map "$SELECTED_DISTRO_PROFILE"; then
        log_error \
            "Unable to load capability mapping: $SELECTED_DISTRO_PROFILE"

        show_failure_info
        return 1
    fi

    log_info \
        "Capability mapping ready: $LWBS_CAPABILITY_PROFILE"

    # Workstation profile selection is introduced separately from the profile
    # framework itself. Loading the framework does not execute any modules.
    if "$LWBS_DRY_RUN"; then
        printf '\nDry-run mode enabled. No system changes will be applied.\n'
    fi

    log_info "Bootstrap foundation completed."

    # Show completion information and the session log location.
    show_completion_info
}

# Determine which supported distribution profile should be used.
select_distro_profile() {
    # A profile explicitly supplied on the command line takes precedence.
    if [[ -n "$LWBS_REQUESTED_DISTRO_PROFILE" ]]; then
        if ! is_supported_distro "$LWBS_REQUESTED_DISTRO_PROFILE"; then
            printf 'Error: unsupported distribution profile: %s\n' \
                "$LWBS_REQUESTED_DISTRO_PROFILE" >&2

            log_error \
                "Unsupported distribution profile requested: $LWBS_REQUESTED_DISTRO_PROFILE"

            return 1
        fi

        SELECTED_DISTRO_PROFILE="$LWBS_REQUESTED_DISTRO_PROFILE"
        return 0
    fi

    # Automatically accept a supported detected profile when --yes is used.
    if "$LWBS_ASSUME_YES"; then
        if is_supported_distro "$SYSTEM_DISTRO_ID"; then
            SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"
            return 0
        fi

        printf 'Error: detected distribution "%s" is not currently supported.\n' \
            "$SYSTEM_DISTRO_ID" >&2

        printf 'Specify a supported profile using --distro.\n' >&2

        log_error \
            "Automatic profile selection failed for unsupported distro: $SYSTEM_DISTRO_ID"

        return 1
    fi

    # Use the detected distribution when it is supported and confirmed.
    if is_supported_distro "$SYSTEM_DISTRO_ID" &&
        confirm_detected_profile; then
        SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"
        return 0
    fi

    # Fall back to interactive profile selection.
    if ! choose_distro_profile; then
        return 1
    fi

    return 0
}