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
# 6. Displays command-line help and version information.

# Clear the terminal when running interactively.
# Non-interactive output, such as CI logs, is left untouched.
clear_screen() {
    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
}

# Display the log location for the current bootstrap session.
show_log_location() {
    printf '  Session log : %s\n' "$LWBS_LOG_FILE"
    printf '  All logs    : %s\n' "$LWBS_LOG_DIR"
}

# Display application information when the bootstrap starts.
show_startup_info() {
    printf '%s %s\n\n' "$LWBS_APP_NAME" "$LWBS_VERSION"

    printf 'Logging is enabled for this session.\n'
    show_log_location

    printf '\n'
}

# Display application information when the bootstrap completes successfully.
show_completion_info() {
    printf '\nBootstrap completed.\n\n'

    printf 'Logs for this run are available at:\n'
    show_log_location

    printf '\n'
}

# Display application information when the bootstrap is cancelled.
show_cancellation_info() {
    printf '\nBootstrap cancelled.\n\n'

    printf 'Logs for this run are available at:\n'
    show_log_location

    printf '\n'
}

# Display application information when the bootstrap stops due to an error.
show_failure_info() {
    printf '\nBootstrap stopped because of an error.\n\n'

    printf 'Logs for this run are available at:\n'
    show_log_location

    printf '\n'
}

# Display the detected system information.
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
profile_name() {
    printf '%s\n' \
        "${LWBS_DISTRO_DISPLAY_NAMES[$1]:-$1}"
}

# Ask whether the user wants to use the automatically detected profile.
confirm_detected_profile() {
    local answer

    printf 'Use the detected %s profile? [Y/n] ' \
        "$(profile_name "$SYSTEM_DISTRO_ID")"

    read -r answer

    case "${answer,,}" in
        "" | y | yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prompt the user to manually select a supported distribution profile.
choose_distro_profile() {
    local choice
    local distro
    local index
    local selected_index

    while true; do
        printf '\nSelect a distribution profile:\n\n'

        # Build the menu from the configured supported distribution profiles.
        index=1

        for distro in "${LWBS_SUPPORTED_DISTROS[@]}"; do
            printf '  %d) %s\n' \
                "$index" \
                "$(profile_name "$distro")"

            ((index += 1))
        done

        printf '  q) Exit\n\n'
        printf 'Selection: '

        read -r choice

        case "${choice,,}" in
            q | quit | exit)
                return 1
                ;;
        esac

        # Allow selection using the displayed menu number.
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            selected_index=$((10#$choice - 1))

            if ((selected_index >= 0 &&
                selected_index < ${#LWBS_SUPPORTED_DISTROS[@]})); then
                SELECTED_DISTRO_PROFILE="${LWBS_SUPPORTED_DISTROS[$selected_index]}"
                return 0
            fi

        # Also allow the distribution ID to be entered directly.
        elif is_supported_distro "${choice,,}"; then
            SELECTED_DISTRO_PROFILE="${choice,,}"
            return 0
        fi

        printf 'Invalid selection. Please try again.\n'
    done
}

# Display command-line usage and supported options.
show_help() {
    cat <<EOF
$LWBS_APP_NAME

Usage:
  ./bin/linux-workstation-bootstrap [options]

Options:
  --distro <profile>   Use a specific distribution profile
  --dry-run            Preview actions without applying system changes
  -y, --yes            Accept a supported detected profile without prompting
  --version            Display the application version
  -h, --help           Display this help

Supported profiles:
$(printf '  %s\n' "${LWBS_SUPPORTED_DISTROS[@]}")

EOF
}

# Display the current application version.
show_version() {
    printf '%s %s\n' "$LWBS_APP_NAME" "$LWBS_VERSION"
}