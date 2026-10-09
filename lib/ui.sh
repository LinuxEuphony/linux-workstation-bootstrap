#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Terminal user interface utilities.
# This file:
# 1. Manages terminal presentation.
# 2. Displays application and logging information.
# 3. Displays detected system information.
# 4. Handles confirmation prompts.
# 5. Allows the user to select a distribution profile.
# 6. Confirms resolved execution plans.
# 7. Displays command-line help and version information.

clear_screen() {
    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
}

show_log_location() {
    printf '  Session log : %s\n' "$LWBS_LOG_FILE"
    printf '  All logs    : %s\n' "$LWBS_LOG_DIR"
}

show_startup_info() {
    printf '%s %s\n\n' "$LWBS_APP_NAME" "$LWBS_VERSION"

    printf 'Logging is enabled for this session.\n'
    show_log_location

    printf '\n'
}

show_completion_info() {
    printf '\nBootstrap completed.\n\n'

    printf 'Logs for this run are available at:\n'
    show_log_location

    printf '\n'
}

show_cancellation_info() {
    printf '\nBootstrap cancelled.\n\n'

    printf 'Logs for this run are available at:\n'
    show_log_location

    printf '\n'
}

show_failure_info() {
    printf '\nBootstrap stopped because of an error.\n\n'

    printf 'Logs for this run are available at:\n'
    show_log_location

    printf '\n'
}

show_system_summary() {
    printf 'Detected system\n\n'

    printf '  Distribution : %s\n' "${SYSTEM_DISTRO_NAME:-unknown}"
    printf '  ID           : %s\n' "${SYSTEM_DISTRO_ID:-unknown}"
    printf '  Version      : %s\n' "${SYSTEM_DISTRO_VERSION:-unknown}"
    printf '  Codename     : %s\n' "${SYSTEM_DISTRO_CODENAME:-unknown}"
    printf '  Architecture : %s\n' "${SYSTEM_ARCH:-unknown}"
    printf '  Family       : %s\n' "${SYSTEM_DISTRO_FAMILY:-unknown}"
    printf '  Package mgr  : %s\n' "${SYSTEM_PACKAGE_MANAGER:-unknown}"

    printf '\n'
}

# Return the configured display name for a distribution profile.
#
# This intentionally does not use the generic name profile_name because
# workstation profile definitions use that function as part of their contract.
distro_profile_name() {
    printf '%s\n' \
        "${LWBS_DISTRO_DISPLAY_NAMES[$1]:-$1}"
}

confirm_detected_profile() {
    local answer

    printf 'Use the detected %s profile? [Y/n] ' \
        "$(distro_profile_name "$SYSTEM_DISTRO_ID")"

    if ! read -r answer; then
        printf '\nError: unable to read distribution profile confirmation.\n' \
            >&2
        return 2
    fi

    case "${answer,,}" in
        "" | y | yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

choose_distro_profile() {
    local choice
    local distro
    local index
    local selected_index

    while true; do
        printf '\nSelect a distribution profile:\n\n'

        index=1

        for distro in "${LWBS_SUPPORTED_DISTROS[@]}"; do
            printf '  %d) %s\n' \
                "$index" \
                "$(distro_profile_name "$distro")"

            ((index += 1))
        done

        printf '  q) Exit\n\n'
        printf 'Selection: '

        if ! read -r choice; then
            printf '\nError: unable to read distribution profile selection.\n' \
                >&2
            return 2
        fi

        case "${choice,,}" in
            q | quit | exit)
                return 1
                ;;
        esac

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            selected_index=$((10#$choice - 1))

            if ((selected_index >= 0 &&
                selected_index < ${#LWBS_SUPPORTED_DISTROS[@]})); then

                SELECTED_DISTRO_PROFILE="${LWBS_SUPPORTED_DISTROS[$selected_index]}"
                return 0
            fi

        elif is_supported_distro "${choice,,}"; then
            SELECTED_DISTRO_PROFILE="${choice,,}"
            return 0
        fi

        printf 'Invalid selection. Please try again.\n'
    done
}

# Confirm a fully resolved execution plan.
#
# --yes explicitly approves the plan without a prompt. Non-interactive
# execution without --yes fails rather than unexpectedly waiting for input.
confirm_execution_plan() {
    local answer

    if "$LWBS_ASSUME_YES"; then
        printf 'Execution plan approved by --yes.\n'
        return 0
    fi

    if [[ ! -t 0 ]]; then
        printf 'Error: non-interactive execution requires --yes to approve the execution plan.\n' \
            >&2

        return 2
    fi

    printf 'Apply this execution plan? [y/N] '

    if ! read -r answer; then
        printf '\nError: unable to read execution-plan confirmation.\n' \
            >&2
        return 2
    fi

    case "${answer,,}" in
        y | yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

show_help() {
    cat <<EOF
$LWBS_APP_NAME

Usage:
  ./bin/linux-workstation-bootstrap [options]

Options:
  --distro <profile>   Use a specific distribution profile
  --dry-run            Preview actions without applying system changes
  -y, --yes            Approve confirmation prompts without interaction
  --version            Display the application version
  -h, --help           Display this help

Supported distribution profiles:
$(printf '  %s\n' "${LWBS_SUPPORTED_DISTROS[@]}")

EOF
}

show_version() {
    printf '%s %s\n' "$LWBS_APP_NAME" "$LWBS_VERSION"
}