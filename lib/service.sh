#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Managed service lifecycle utilities.
#
# This file exposes a sourced library API whose functions are invoked from
# other bootstrap layers.
# shellcheck disable=SC2317,SC2329
#
# Provides read-only service-state discovery and controlled service actions
# for modules that declare required systemd service state.

service_manager_available() {
    local runtime_dir="${LWBS_SYSTEMD_RUNTIME_DIR_OVERRIDE:-/run/systemd/system}"

    command_exists systemctl && [[ -d "$runtime_dir" ]]
}

validate_service_name() {
    local service_name="${1:-}"

    [[ "$service_name" =~ ^[A-Za-z0-9_.@:-]+\.service$ ]]
}

parse_service_requirement() {
    local requirement="${1:-}"
    local service_name_var="${2:-}"
    local enabled_state_var="${3:-}"
    local active_state_var="${4:-}"
    local restart_policy_var="${5:-}"
    local parsed_service_name
    local parsed_enabled_state
    local parsed_active_state
    local parsed_restart_policy
    local extra
    local output_name

    for output_name in \
        "$service_name_var" \
        "$enabled_state_var" \
        "$active_state_var" \
        "$restart_policy_var"; do

        if [[ ! "$output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf 'Error: invalid service requirement output variable: %s\n' \
                "$output_name" >&2
            return 2
        fi
    done

    read -r \
        parsed_service_name \
        parsed_enabled_state \
        parsed_active_state \
        parsed_restart_policy \
        extra <<<"$requirement"

    if [[ -z "$parsed_service_name" ||
        -z "$parsed_enabled_state" ||
        -z "$parsed_active_state" ||
        -z "$parsed_restart_policy" ||
        -n "$extra" ]]; then

        printf 'Error: invalid service requirement: %s\n' "$requirement" >&2
        return 2
    fi

    if ! validate_service_name "$parsed_service_name"; then
        printf 'Error: invalid service name: %s\n' "$parsed_service_name" >&2
        return 2
    fi

    case "$parsed_enabled_state" in
        enabled | disabled | unchanged) ;;
        *)
            printf 'Error: invalid service enabled state for %s: %s\n' \
                "$parsed_service_name" \
                "$parsed_enabled_state" >&2
            return 2
            ;;
    esac

    case "$parsed_active_state" in
        active | inactive | unchanged) ;;
        *)
            printf 'Error: invalid service active state for %s: %s\n' \
                "$parsed_service_name" \
                "$parsed_active_state" >&2
            return 2
            ;;
    esac

    case "$parsed_restart_policy" in
        never | on-change) ;;
        *)
            printf 'Error: invalid service restart policy for %s: %s\n' \
                "$parsed_service_name" \
                "$parsed_restart_policy" >&2
            return 2
            ;;
    esac

    if [[ "$parsed_restart_policy" == "on-change" &&
        "$parsed_active_state" != "active" ]]; then

        printf 'Error: on-change restart requires active service state: %s\n' \
            "$parsed_service_name" >&2
        return 2
    fi

    if [[ "$parsed_enabled_state" == "unchanged" &&
        "$parsed_active_state" == "unchanged" &&
        "$parsed_restart_policy" == "never" ]]; then

        printf 'Error: service requirement does not request any state: %s\n' \
            "$parsed_service_name" >&2
        return 2
    fi

    local -n service_name_ref="$service_name_var"
    local -n enabled_state_ref="$enabled_state_var"
    local -n active_state_ref="$active_state_var"
    local -n restart_policy_ref="$restart_policy_var"

    service_name_ref="$parsed_service_name"
    enabled_state_ref="$parsed_enabled_state"
    active_state_ref="$parsed_active_state"
    restart_policy_ref="$parsed_restart_policy"

    return 0
}

query_service_presence() {
    local service_name="${1:-}"
    local load_state
    local exit_code

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    if load_state="$(
        systemctl show \
            --property=LoadState \
            --value \
            "$service_name" \
            2>/dev/null
    )"; then
        :
    else
        exit_code=$?
        printf 'Error: unable to query service: %s\n' "$service_name" >&2
        return "$exit_code"
    fi

    case "$load_state" in
        not-found | "")
            printf '%s\n' "absent"
            ;;
        *)
            printf '%s\n' "present"
            ;;
    esac
}

query_service_enabled_state() {
    local service_name="${1:-}"
    local state
    local exit_code=0

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    if state="$(systemctl is-enabled "$service_name" 2>/dev/null)"; then
        :
    else
        exit_code=$?
    fi

    case "$state" in
        enabled | enabled-runtime | linked | linked-runtime | alias)
            printf '%s\n' "enabled"
            return 0
            ;;
        disabled | masked | masked-runtime | static | indirect | generated | transient)
            printf '%s\n' "disabled"
            return 0
            ;;
        *)
            printf 'Error: unable to determine enabled state for service %s.\n' \
                "$service_name" >&2
            if ((exit_code == 0)); then
                exit_code=1
            fi
            return "$exit_code"
            ;;
    esac
}

query_service_active_state() {
    local service_name="${1:-}"
    local state
    local exit_code=0

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    if state="$(systemctl is-active "$service_name" 2>/dev/null)"; then
        :
    else
        exit_code=$?
    fi

    case "$state" in
        active | reloading | activating)
            printf '%s\n' "active"
            return 0
            ;;
        inactive | failed | deactivating | maintenance)
            printf '%s\n' "inactive"
            return 0
            ;;
        *)
            printf 'Error: unable to determine active state for service %s.\n' \
                "$service_name" >&2
            if ((exit_code == 0)); then
                exit_code=1
            fi
            return "$exit_code"
            ;;
    esac
}

service_requirement_is_satisfied() {
    local service_name="${1:-}"
    local required_enabled="${2:-unchanged}"
    local required_active="${3:-unchanged}"
    local presence
    local current_state

    if presence="$(query_service_presence "$service_name")"; then
        :
    else
        return 2
    fi

    if [[ "$presence" != "present" ]]; then
        return 1
    fi

    if [[ "$required_enabled" != "unchanged" ]]; then
        if current_state="$(query_service_enabled_state "$service_name")"; then
            :
        else
            return 2
        fi

        if [[ "$current_state" != "$required_enabled" ]]; then
            return 1
        fi
    fi

    if [[ "$required_active" != "unchanged" ]]; then
        if current_state="$(query_service_active_state "$service_name")"; then
            :
        else
            return 2
        fi

        if [[ "$current_state" != "$required_active" ]]; then
            return 1
        fi
    fi

    return 0
}

service_enable() {
    local service_name="${1:-}"

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    run_privileged_command systemctl enable "$service_name"
}

service_disable() {
    local service_name="${1:-}"

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    run_privileged_command systemctl disable "$service_name"
}

service_start() {
    local service_name="${1:-}"

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    run_privileged_command systemctl start "$service_name"
}

service_stop() {
    local service_name="${1:-}"

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    run_privileged_command systemctl stop "$service_name"
}

service_restart() {
    local service_name="${1:-}"

    if ! service_manager_available; then
        printf 'Error: systemd service management is unavailable.\n' >&2
        return 1
    fi

    if ! validate_service_name "$service_name"; then
        printf 'Error: invalid service name: %s\n' "$service_name" >&2
        return 2
    fi

    run_privileged_command systemctl restart "$service_name"
}
