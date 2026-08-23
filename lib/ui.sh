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
    printf 'Linux Workstation Bootstrap %s\n\n' "$LWBS_VERSION"

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

# Return a friendly display name for a supported distribution profile.
profile_name() {
    case "$1" in
        ubuntu)
            printf 'Ubuntu\n'
            ;;
        debian)
            printf 'Debian\n'
            ;;
        kali)
            printf 'Kali Linux\n'
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
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

    while true; do
        printf '\nSelect a distribution profile:\n\n'
        printf '  1) Ubuntu\n'
        printf '  2) Debian\n'
        printf '  3) Kali Linux\n'
        printf '  q) Exit\n\n'
        printf 'Selection: '

        read -r choice

        case "${choice,,}" in
            1 | ubuntu)
                SELECTED_DISTRO_PROFILE="ubuntu"
                return 0
                ;;
            2 | debian)
                SELECTED_DISTRO_PROFILE="debian"
                return 0
                ;;
            3 | kali)
                SELECTED_DISTRO_PROFILE="kali"
                return 0
                ;;
            q | quit | exit)
                return 1
                ;;
            *)
                printf 'Invalid selection. Please try again.\n'
                ;;
        esac
    done
}