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

# shellcheck source=./lock.sh
source "$LWBS_ROOT/lib/lock.sh"

# shellcheck source=./recovery.sh
source "$LWBS_ROOT/lib/recovery.sh"

# shellcheck source=./restart.sh
source "$LWBS_ROOT/lib/restart.sh"

# shellcheck source=./account.sh
source "$LWBS_ROOT/lib/account.sh"

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

# shellcheck source=./configuration.sh
source "$LWBS_ROOT/lib/configuration.sh"

# shellcheck source=./module.sh
source "$LWBS_ROOT/lib/module.sh"

# shellcheck source=./module-graph.sh
source "$LWBS_ROOT/lib/module-graph.sh"

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

# shellcheck source=./preflight.sh
source "$LWBS_ROOT/lib/preflight.sh"

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

    if ! initialize_application_state; then
        return 1
    fi

    if acquire_execution_lock; then
        :
    else
        return $?
    fi

    lock_install_exit_handler

    if init_logging; then
        :
    else
        return $?
    fi

    log_info \
        "Bootstrap execution lock acquired: pid=$LWBS_LOCK_OWNER_PID"

    show_startup_info

    if recovery_detect_previous_run; then
        :
    else
        exit_code=$?

        log_error \
            "Recovery state initialization failed: exit_code=$exit_code"

        show_failure_info
        return "$exit_code"
    fi

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

    if ! initialize_target_workstation_user; then
        log_error "Target workstation user resolution failed."
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

    if select_distro_profile; then
        :
    else
        exit_code=$?

        if ((exit_code == 1)); then
            log_info "Bootstrap cancelled by user."
            show_cancellation_info
            return 0
        fi

        log_error \
            "Distribution profile selection failed: exit_code=$exit_code"

        show_failure_info
        return "$exit_code"
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

    printf 'Target workstation user: %s\n' \
        "$LWBS_TARGET_USER"

    log_info \
        "Selected workstation profile: $workstation_profile"

    if validate_profile_preflight "$workstation_profile"; then
        :
    else
        exit_code=$?

        log_error \
            "Bootstrap preflight failed: profile=$workstation_profile exit_code=$exit_code"

        show_failure_info
        return "$exit_code"
    fi

    if "$LWBS_DRY_RUN"; then
        printf 'Dry-run mode enabled. No system changes will be applied.\n'
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

    return 0
}

select_distro_profile() {
    local confirmation_exit_code
    local selection_exit_code

    if [[ -n "$LWBS_REQUESTED_DISTRO_PROFILE" ]]; then
        if ! is_supported_distro "$LWBS_REQUESTED_DISTRO_PROFILE"; then
            printf 'Error: unsupported distribution profile: %s\n' \
                "$LWBS_REQUESTED_DISTRO_PROFILE" >&2

            return 2
        fi

        SELECTED_DISTRO_PROFILE="$LWBS_REQUESTED_DISTRO_PROFILE"

        return 0
    fi

    if [[ -n "${LWBS_CONFIG_DISTRO_PROFILE:-}" &&
        "$LWBS_CONFIG_DISTRO_PROFILE" != "auto" ]]; then

        if ! is_supported_distro "$LWBS_CONFIG_DISTRO_PROFILE"; then
            printf 'Error: configured distribution profile is unsupported: %s\n' \
                "$LWBS_CONFIG_DISTRO_PROFILE" >&2

            return 2
        fi

        SELECTED_DISTRO_PROFILE="$LWBS_CONFIG_DISTRO_PROFILE"

        return 0
    fi

    if "$LWBS_ASSUME_YES"; then
        if is_supported_distro "$SYSTEM_DISTRO_ID"; then
            SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"

            return 0
        fi

        printf 'Error: detected distribution "%s" is not currently supported.\n' \
            "$SYSTEM_DISTRO_ID" >&2

        return 2
    fi

    if is_supported_distro "$SYSTEM_DISTRO_ID"; then
        if confirm_detected_profile; then
            SELECTED_DISTRO_PROFILE="$SYSTEM_DISTRO_ID"

            return 0
        else
            confirmation_exit_code=$?

            if ((confirmation_exit_code != 1)); then
                return "$confirmation_exit_code"
            fi
        fi
    fi

    if choose_distro_profile; then
        return 0
    else
        selection_exit_code=$?

        return "$selection_exit_code"
    fi
}
