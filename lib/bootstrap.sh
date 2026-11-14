#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Main application bootstrap.
# Coordinates the shared bootstrap layers without embedding distribution-
# specific installation logic in the application entry flow.

# shellcheck source=../config/defaults.sh
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

# shellcheck source=./service.sh
source "$LWBS_ROOT/lib/service.sh"

# shellcheck source=./hardware.sh
source "$LWBS_ROOT/lib/hardware.sh"

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

# shellcheck source=./verification.sh
source "$LWBS_ROOT/lib/verification.sh"

# shellcheck source=./service-plan.sh
source "$LWBS_ROOT/lib/service-plan.sh"

# shellcheck source=./plan.sh
source "$LWBS_ROOT/lib/plan.sh"

SELECTED_DISTRO_PROFILE=""

bootstrap_main() {
    local workstation_profile
    local exit_code

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
        list-profiles)
            show_available_profiles
            return $?
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

    printf 'Selected distribution profile: %s\n' \
        "$(distro_profile_name "$SELECTED_DISTRO_PROFILE")"

    if [[ "$SELECTED_DISTRO_PROFILE" != "$SYSTEM_DISTRO_ID" ]]; then
        printf 'Profile override: detected %s, selected %s\n' \
            "$SYSTEM_DISTRO_ID" \
            "$SELECTED_DISTRO_PROFILE"

        log_warning \
            "Distribution profile override: detected=$SYSTEM_DISTRO_ID selected=$SELECTED_DISTRO_PROFILE"
    fi

    if ! load_distro_adapter "$SELECTED_DISTRO_PROFILE"; then
        show_failure_info
        return 1
    fi

    if ! distro_validate_environment; then
        show_failure_info
        return 1
    fi

    if ! load_capability_map "$SELECTED_DISTRO_PROFILE"; then
        show_failure_info
        return 1
    fi

    workstation_profile="${LWBS_REQUESTED_WORKSTATION_PROFILE:-$LWBS_DEFAULT_WORKSTATION_PROFILE}"

    printf 'Selected workstation profile: %s\n' \
        "$workstation_profile"

    log_info \
        "Selected workstation profile: $workstation_profile"

    if "$LWBS_DRY_RUN"; then
        printf '\nDry-run mode enabled. No system changes will be applied.\n'
    fi

    if run_profile "$workstation_profile"; then
        :
    else
        exit_code=$?

        log_error \
            "Workstation profile execution failed: profile=$workstation_profile exit_code=$exit_code"

        show_failure_info
        return "$exit_code"
    fi

    if [[ "$LWBS_PLAN_STATUS" == "cancelled" ]]; then
        log_info "Bootstrap cancelled during execution-plan confirmation."
        show_cancellation_info
        return 0
    fi

    log_info \
        "Bootstrap completed: profile=$workstation_profile status=$LWBS_PLAN_STATUS"

    show_completion_info
}
