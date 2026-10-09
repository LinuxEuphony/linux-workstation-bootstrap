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
# 4. Loads optional user configuration.
# 5. Validates the runtime environment.
# 6. Coordinates system detection.
# 7. Determines the distribution profile to use.
# 8. Loads and validates the selected distribution adapter.
# 9. Loads package capability mappings for the selected distribution.
# 10. Exposes external software installation.
# 11. Exposes workstation modules and profiles.
# 12. Exposes resolved execution planning and confirmation.
# 13. Controls the main bootstrap execution flow.

source "$LWBS_ROOT/config/defaults.sh"

# shellcheck source=./config.sh
source "$LWBS_ROOT/lib/config.sh"

# shellcheck source=./arguments.sh
source "$LWBS_ROOT/lib/arguments.sh"

# shellcheck source=./logging.sh
source "$LWBS_ROOT/lib/logging.sh"

# shellcheck source=./core.sh
source "$LWBS_ROOT/lib/core.sh"

# shellcheck source=./execution.sh
source "$LWBS_ROOT/lib/execution.sh"

# shellcheck source=./distro.sh
source "$LWBS_ROOT/lib/distro.sh"

# shellcheck source=./capability.sh
source "$LWBS_ROOT/lib/capability.sh"

# shellcheck source=./external.sh
source "$LWBS_ROOT/lib/external.sh"

# shellcheck source=./module.sh
source "$LWBS_ROOT/lib/module.sh"

# shellcheck source=./profile.sh
source "$LWBS_ROOT/lib/profile.sh"

# shellcheck source=./detect.sh
source "$LWBS_ROOT/lib/detect.sh"

# shellcheck source=./ui.sh
source "$LWBS_ROOT/lib/ui.sh"

# shellcheck source=./plan.sh
source "$LWBS_ROOT/lib/plan.sh"

SELECTED_DISTRO_PROFILE=""

bootstrap_main() {
    clear_screen

    if ! parse_arguments "$@"; then
        printf '\nUse --help to view supported options.\n' >&2
        return 2
    fi

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

    init_logging
    show_startup_info

    log_info "$LWBS_APP_NAME $LWBS_VERSION started."

    if "$LWBS_DRY_RUN"; then
        log_info "Dry-run mode enabled."
    fi

    if ! load_user_config; then
        log_error "User configuration validation failed."
        show_failure_info
        return 1
    fi

    if ! validate_runtime; then
        log_error "Runtime validation failed."
        show_failure_info
        return 1
    fi

    if ! detect_system; then
        log_error "System detection failed."
        show_failure_info
        return 1
    fi

    log_info \
        "Detected system: distro=$SYSTEM_DISTRO_ID version=$SYSTEM_DISTRO_VERSION codename=$SYSTEM_DISTRO_CODENAME architecture=$SYSTEM_ARCH family=$SYSTEM_DISTRO_FAMILY package_manager=$SYSTEM_PACKAGE_MANAGER"

    show_system_summary

    if ! select_distro_profile; then
        log_info "Bootstrap cancelled by user."
        show_cancellation_info
        return 0
    fi

    log_info \
        "Selected distribution profile: $SELECTED_DISTRO_PROFILE"

    printf 'Selected profile: %s\n' \
        "$(distro_profile_name "$SELECTED_DISTRO_PROFILE")"

    if [[ "$SELECTED_DISTRO_PROFILE" != "$SYSTEM_DISTRO_ID" ]]; then
        printf 'Profile override: detected %s, selected %s\n' \
            "$SYSTEM_DISTRO_ID" \
            "$SELECTED_DISTRO_PROFILE"

        log_warning \
            "Distribution profile override: detected=$SYSTEM_DISTRO_ID selected=$SELECTED_DISTRO_PROFILE"
    fi

    if ! load_distro_adapter "$SELECTED_DISTRO_PROFILE"; then
        log_error \
            "Unable to load distribution adapter: $SELECTED_DISTRO_PROFILE"

        show_failure_info
        return 1
    fi

    if ! distro_validate_environment; then
        log_error \
            "Distribution adapter environment validation failed: $SELECTED_DISTRO_PROFILE"

        show_failure_info
        return 1
    fi

    log_info \
        "Distribution adapter ready: $DISTRO_ADAPTER_PROFILE"

    if ! load_capability_map "$SELECTED_DISTRO_PROFILE"; then
        log_error \
            "Unable to load capability mapping: $SELECTED_DISTRO_PROFILE"

        show_failure_info
        return 1
    fi

    log_info \
        "Capability mapping ready: $LWBS_CAPABILITY_PROFILE"

    # Workstation profile selection is added separately. Once a workstation
    # profile is selected, run_profile() routes it through the mandatory
    # execution-plan workflow before any installation is attempted.
    if "$LWBS_DRY_RUN"; then
        printf '\nDry-run mode enabled. No system changes will be applied.\n'
    fi

    log_info "Bootstrap foundation completed."

    show_completion_info
}

select_distro_profile() {
    if [[ -n "$LWBS_REQUESTED_DISTRO_PROFILE" ]]; then
        if ! is_supported_distro "$LWBS_REQUESTED_DISTRO_PROFILE"; then
            printf 'Error: unsupported distribution profile: %s\n' \
                "$LWBS_REQUESTED_DISTRO_PROFILE" >&2

            return 1
        fi

        SELECTED_DISTRO_PROFILE="$LWBS_REQUESTED_DISTRO_PROFILE"

        log_info \
            "Distribution profile selected from CLI: $SELECTED_DISTRO_PROFILE"

        return 0
    fi

    if [[ -n "${LWBS_CONFIG_DISTRO_PROFILE:-}" &&
        "$LWBS_CONFIG_DISTRO_PROFILE" != "auto" ]]; then

        SELECTED_DISTRO_PROFILE="$LWBS_CONFIG_DISTRO_PROFILE"

        log_info \
            "Distribution profile selected from user configuration: $SELECTED_DISTRO_PROFILE"

        return 0
    fi

    if "$LWBS_ASSUME_YES"; then
        if is_supported_distro "$SYSTEM_DISTRO_ID"; then
            SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"
            return 0
        fi

        printf 'Error: detected distribution "%s" is not currently supported.\n' \
            "$SYSTEM_DISTRO_ID" >&2

        printf 'Specify a supported profile using --distro.\n' >&2

        return 1
    fi

    if is_supported_distro "$SYSTEM_DISTRO_ID" &&
        confirm_detected_profile; then

        SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"
        return 0
    fi

    if ! choose_distro_profile; then
        return 1
    fi

    return 0
}