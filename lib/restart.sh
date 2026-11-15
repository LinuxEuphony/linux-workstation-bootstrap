#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Restart and session follow-up requirement tracking.
#
# Modules and external installers may declare follow-up actions that become
# necessary after successful changes.
#
# Supported requirement types:
#
#   reboot
#   logout
#   shell
#   application
#
# Declaration format:
#
#   type|target|reason
#
# Canonical targets:
#
#   reboot      -> system
#   logout      -> user-session
#   shell       -> current-shell
#   application -> application display name or identifier
#
# Restart requirements are informational only. This framework never performs
# a reboot, logout, shell termination, or application restart.
#
# SC2178 is disabled because this file intentionally uses dynamic namerefs
# that may reference either indexed or associative arrays.
#
# shellcheck disable=SC2154,SC2178

LWBS_PLAN_RESTART_REQUIREMENT_COUNT=0

declare -A LWBS_PLAN_MODULE_RESTART_REQUIREMENTS=()
declare -A LWBS_PLAN_EXTERNAL_RESTART_REQUIREMENTS=()

declare -a LWBS_PLANNED_RESTART_KEYS=()
declare -A LWBS_PLANNED_RESTART_TYPE=()
declare -A LWBS_PLANNED_RESTART_TARGET=()
declare -A LWBS_PLANNED_RESTART_REASONS=()
declare -A LWBS_PLANNED_RESTART_REASON_SET=()

declare -a LWBS_RESTART_KEYS=()
declare -A LWBS_RESTART_TYPE=()
declare -A LWBS_RESTART_TARGET=()
declare -A LWBS_RESTART_REASONS=()
declare -A LWBS_RESTART_REASON_SET=()

restart_requirement_key() {
    printf '%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

parse_restart_requirement() {
    local requirement="${1:-}"
    local type_name="${2:-}"
    local target_name="${3:-}"
    local reason_name="${4:-}"

    local parsed_type
    local parsed_target
    local parsed_reason
    local extra

    if [[ -z "$requirement" ||
        -z "$type_name" ||
        -z "$target_name" ||
        -z "$reason_name" ]]; then

        printf 'Error: incomplete restart requirement parser request.\n' >&2
        return 2
    fi

    IFS='|' read -r \
        parsed_type \
        parsed_target \
        parsed_reason \
        extra <<<"$requirement"

    if [[ -n "$extra" ]]; then
        printf 'Error: restart requirement has too many fields.\n' >&2
        return 1
    fi

    case "$parsed_type" in
        reboot)
            if [[ "$parsed_target" != "system" ]]; then
                printf 'Error: reboot requirement target must be "system".\n' \
                    >&2
                return 1
            fi
            ;;

        logout)
            if [[ "$parsed_target" != "user-session" ]]; then
                printf 'Error: logout requirement target must be "user-session".\n' \
                    >&2
                return 1
            fi
            ;;

        shell)
            if [[ "$parsed_target" != "current-shell" ]]; then
                printf 'Error: shell restart requirement target must be "current-shell".\n' \
                    >&2
                return 1
            fi
            ;;

        application)
            if [[ -z "$parsed_target" ]]; then
                printf 'Error: application restart requirement requires an application target.\n' \
                    >&2
                return 1
            fi
            ;;

        *)
            printf 'Error: unsupported restart requirement type: %s\n' \
                "$parsed_type" >&2
            return 1
            ;;
    esac

    if [[ -z "$parsed_reason" ]]; then
        printf 'Error: restart requirement requires a reason.\n' >&2
        return 1
    fi

    local -n type_ref="$type_name"
    local -n target_ref="$target_name"
    local -n reason_ref="$reason_name"

    type_ref="$parsed_type"
    target_ref="$parsed_target"
    reason_ref="$parsed_reason"

    return 0
}

restart_add_to_collection() {
    local keys_name="${1:-}"
    local type_map_name="${2:-}"
    local target_map_name="${3:-}"
    local reasons_map_name="${4:-}"
    local reason_set_name="${5:-}"
    local requirement_type="${6:-}"
    local target="${7:-}"
    local reason="${8:-}"

    local requirement_key
    local reason_key

    local -n keys_ref="$keys_name"
    local -n type_map_ref="$type_map_name"
    local -n target_map_ref="$target_map_name"
    local -n reasons_map_ref="$reasons_map_name"
    local -n reason_set_ref="$reason_set_name"

    requirement_key="$(
        restart_requirement_key \
            "$requirement_type" \
            "$target"
    )"

    reason_key="${requirement_key}::${reason}"

    if [[ -z "${type_map_ref[$requirement_key]+defined}" ]]; then
        keys_ref+=("$requirement_key")
        type_map_ref["$requirement_key"]="$requirement_type"
        target_map_ref["$requirement_key"]="$target"
        reasons_map_ref["$requirement_key"]=""
    fi

    if [[ -n "${reason_set_ref[$reason_key]+defined}" ]]; then
        return 0
    fi

    reason_set_ref["$reason_key"]=1

    if [[ -n "${reasons_map_ref[$requirement_key]}" ]]; then
        reasons_map_ref["$requirement_key"]+=$'\n'"$reason"
    else
        reasons_map_ref["$requirement_key"]="$reason"
    fi

    return 0
}

restart_add_planned_requirement() {
    local requirement_type="${1:-}"
    local target="${2:-}"
    local reason="${3:-}"

    restart_add_to_collection \
        LWBS_PLANNED_RESTART_KEYS \
        LWBS_PLANNED_RESTART_TYPE \
        LWBS_PLANNED_RESTART_TARGET \
        LWBS_PLANNED_RESTART_REASONS \
        LWBS_PLANNED_RESTART_REASON_SET \
        "$requirement_type" \
        "$target" \
        "$reason"

    LWBS_PLAN_RESTART_REQUIREMENT_COUNT="${#LWBS_PLANNED_RESTART_KEYS[@]}"

    log_info \
        "Planned follow-up requirement: type=$requirement_type target=$target reason=$reason"
}

restart_add_recorded_requirement() {
    local requirement_type="${1:-}"
    local target="${2:-}"
    local reason="${3:-}"

    local before_count

    before_count="${#LWBS_RESTART_KEYS[@]}"

    restart_add_to_collection \
        LWBS_RESTART_KEYS \
        LWBS_RESTART_TYPE \
        LWBS_RESTART_TARGET \
        LWBS_RESTART_REASONS \
        LWBS_RESTART_REASON_SET \
        "$requirement_type" \
        "$target" \
        "$reason"

    if ((${#LWBS_RESTART_KEYS[@]} > before_count)); then
        log_info \
            "Follow-up requirement recorded: type=$requirement_type target=$target reason=$reason"
    else
        log_info \
            "Follow-up requirement updated: type=$requirement_type target=$target reason=$reason"
    fi
}

restart_module_has_planned_changes() {
    local module_id="${1:-}"
    local installer_id
    local external_key
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy
    local service_key

    if [[ -n "${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}" ]]; then
        return 0
    fi

    if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" == "true" ]]; then
        return 0
    fi

    if module_has_planned_configuration_changes "$module_id"; then
        return 0
    fi

    while IFS= read -r installer_id; do
        [[ -z "$installer_id" ]] && continue

        external_key="$(
            execution_plan_external_key \
                "$module_id" \
                "$installer_id"
        )"

        if [[ "${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-}" == "install" ]]; then
            return 0
        fi
    done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"

    while IFS= read -r service_requirement; do
        [[ -z "$service_requirement" ]] && continue

        parse_service_requirement \
            "$service_requirement" \
            service_name \
            enabled_state \
            active_state \
            restart_policy

        service_key="$(
            execution_plan_service_key \
                "$module_id" \
                "$service_name"
        )"

        if [[ "${LWBS_PLAN_SERVICE_ACTIONS[$service_key]:-skip}" != "skip" ]]; then
            return 0
        fi
    done <<<"${LWBS_PLAN_MODULE_SERVICES[$module_id]:-}"

    return 1
}

restart_module_execution_changed() {
    local module_id="${1:-}"
    local result_key

    if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" == "true" ]]; then
        return 0
    fi

    for result_key in "${LWBS_RESULT_KEYS[@]}"; do
        if [[ "${LWBS_RESULT_MODULE[$result_key]:-}" != "$module_id" ]]; then
            continue
        fi

        case "${LWBS_RESULT_TYPE[$result_key]:-}" in
            package | external | configuration | service)
                if [[ "${LWBS_RESULT_STATUS[$result_key]:-}" == "successful" ]]; then
                    return 0
                fi
                ;;
        esac
    done

    return 1
}

plan_module_restart_requirements() {
    local module_id="${1:-}"
    local requirement
    local requirement_type
    local target
    local reason

    for requirement in "${LWBS_MODULE_RESTART_REQUIREMENTS[@]}"; do
        if parse_restart_requirement \
            "$requirement" \
            requirement_type \
            target \
            reason; then
            :
        else
            return $?
        fi

        append_execution_plan_value \
            LWBS_PLAN_MODULE_RESTART_REQUIREMENTS \
            "$module_id" \
            "$requirement"

        if restart_module_has_planned_changes "$module_id"; then
            restart_add_planned_requirement \
                "$requirement_type" \
                "$target" \
                "$reason"
        fi
    done

    return 0
}

plan_external_restart_requirements() {
    local module_id="${1:-}"
    local installer_id="${2:-}"
    local external_key="${3:-}"

    local requirement
    local requirement_type
    local target
    local reason

    if ! declare -p LWBS_EXTERNAL_RESTART_REQUIREMENTS >/dev/null 2>&1; then
        return 0
    fi

    for requirement in "${LWBS_EXTERNAL_RESTART_REQUIREMENTS[@]}"; do
        if parse_restart_requirement \
            "$requirement" \
            requirement_type \
            target \
            reason; then
            :
        else
            return $?
        fi

        append_execution_plan_value \
            LWBS_PLAN_EXTERNAL_RESTART_REQUIREMENTS \
            "$external_key" \
            "$requirement"

        if [[ "${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-}" == "install" ]]; then
            restart_add_planned_requirement \
                "$requirement_type" \
                "$target" \
                "$reason"
        fi
    done

    log_info \
        "External restart requirements planned: module=$module_id installer=$installer_id count=${#LWBS_EXTERNAL_RESTART_REQUIREMENTS[@]}"

    return 0
}

record_external_restart_requirements() {
    local module_id="${1:-}"
    local installer_id="${2:-}"
    local external_key="${3:-}"

    local requirement
    local requirement_type
    local target
    local reason

    while IFS= read -r requirement; do
        [[ -z "$requirement" ]] && continue

        if parse_restart_requirement \
            "$requirement" \
            requirement_type \
            target \
            reason; then
            :
        else
            return $?
        fi

        restart_add_recorded_requirement \
            "$requirement_type" \
            "$target" \
            "$reason"
    done <<<"${LWBS_PLAN_EXTERNAL_RESTART_REQUIREMENTS[$external_key]:-}"

    log_info \
        "External follow-up requirements recorded: module=$module_id installer=$installer_id"

    return 0
}

record_module_restart_requirements() {
    local module_id="${1:-}"
    local requirement
    local requirement_type
    local target
    local reason

    if ! restart_module_execution_changed "$module_id"; then
        return 0
    fi

    while IFS= read -r requirement; do
        [[ -z "$requirement" ]] && continue

        if parse_restart_requirement \
            "$requirement" \
            requirement_type \
            target \
            reason; then
            :
        else
            return $?
        fi

        restart_add_recorded_requirement \
            "$requirement_type" \
            "$target" \
            "$reason"
    done <<<"${LWBS_PLAN_MODULE_RESTART_REQUIREMENTS[$module_id]:-}"

    return 0
}

restart_requirement_label() {
    local requirement_type="${1:-}"
    local target="${2:-}"

    case "$requirement_type" in
        reboot)
            printf '%s\n' "System reboot"
            ;;

        logout)
            printf '%s\n' "Log out and back in"
            ;;

        shell)
            printf '%s\n' "Restart current shell"
            ;;

        application)
            printf 'Restart application: %s\n' "$target"
            ;;

        *)
            printf '%s\n' "$requirement_type"
            ;;
    esac
}

show_restart_collection() {
    local title="${1:-}"
    local keys_name="${2:-}"
    local type_map_name="${3:-}"
    local target_map_name="${4:-}"
    local reasons_map_name="${5:-}"

    local requirement_key
    local reason
    local label

    local -n keys_ref="$keys_name"
    local -n type_map_ref="$type_map_name"
    local -n target_map_ref="$target_map_name"
    local -n reasons_map_ref="$reasons_map_name"

    printf '\n%s\n\n' "$title"

    if ((${#keys_ref[@]} == 0)); then
        printf '  None.\n\n'
        return 0
    fi

    for requirement_key in "${keys_ref[@]}"; do
        label="$(
            restart_requirement_label \
                "${type_map_ref[$requirement_key]}" \
                "${target_map_ref[$requirement_key]}"
        )"

        printf '  %s\n' "$label"

        while IFS= read -r reason; do
            [[ -z "$reason" ]] && continue
            printf '    - %s\n' "$reason"
        done <<<"${reasons_map_ref[$requirement_key]}"
    done

    printf '\n'
}

show_planned_restart_requirements() {
    show_restart_collection \
        "Potential follow-up requirements" \
        LWBS_PLANNED_RESTART_KEYS \
        LWBS_PLANNED_RESTART_TYPE \
        LWBS_PLANNED_RESTART_TARGET \
        LWBS_PLANNED_RESTART_REASONS
}

show_recorded_restart_requirements() {
    show_restart_collection \
        "Follow-up requirements" \
        LWBS_RESTART_KEYS \
        LWBS_RESTART_TYPE \
        LWBS_RESTART_TARGET \
        LWBS_RESTART_REASONS
}

show_execution_outcome() {
    show_execution_summary
    show_recorded_restart_requirements
}

reset_planned_restart_requirements() {
    LWBS_PLAN_RESTART_REQUIREMENT_COUNT=0

    LWBS_PLAN_MODULE_RESTART_REQUIREMENTS=()
    LWBS_PLAN_EXTERNAL_RESTART_REQUIREMENTS=()

    LWBS_PLANNED_RESTART_KEYS=()
    LWBS_PLANNED_RESTART_TYPE=()
    LWBS_PLANNED_RESTART_TARGET=()
    LWBS_PLANNED_RESTART_REASONS=()
    LWBS_PLANNED_RESTART_REASON_SET=()
}

reset_recorded_restart_requirements() {
    LWBS_RESTART_KEYS=()
    LWBS_RESTART_TYPE=()
    LWBS_RESTART_TARGET=()
    LWBS_RESTART_REASONS=()
    LWBS_RESTART_REASON_SET=()
}

reset_restart_tracking() {
    reset_planned_restart_requirements
    reset_recorded_restart_requirements
}
