#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Service execution-plan integration.
#
# This sourced library consumes plan, module, and verification state declared
# by other bootstrap layers and exposes hooks invoked by lib/plan.sh.
# shellcheck disable=SC2154,SC2317,SC2329
#
# Keeps service-specific planning, execution, and verification logic separate
# from the generic execution-plan orchestrator.

LWBS_PLAN_SERVICE_ACTION_COUNT=0

declare -A LWBS_PLAN_MODULE_SERVICES=()
declare -A LWBS_PLAN_SERVICE_ACTIONS=()

execution_plan_service_key() {
    printf '%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

service_result_key() {
    local module_id="${1:-}"
    local service_name="${2:-}"

    printf 'service::%s::%s\n' \
        "$module_id" \
        "$service_name"
}

module_has_planned_changes() {
    local module_id="${1:-}"
    local installer_id
    local external_key

    if [[ -n "${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}" ]]; then
        return 0
    fi

    if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" == "true" ]]; then
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

    return 1
}

module_execution_changed() {
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
            package | external)
                if [[ "${LWBS_RESULT_STATUS[$result_key]:-}" == "successful" ]]; then
                    return 0
                fi
                ;;
        esac
    done

    return 1
}

plan_module_services() {
    local module_id="${1:-}"
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy
    local service_key
    local presence
    local current_enabled
    local current_active
    local exit_code
    local planned_action
    local has_planned_changes=false

    local -a planned_actions=()

    if module_has_planned_changes "$module_id"; then
        has_planned_changes=true
    fi

    for service_requirement in "${LWBS_MODULE_SERVICES[@]}"; do
        parse_service_requirement \
            "$service_requirement" \
            service_name \
            enabled_state \
            active_state \
            restart_policy

        append_execution_plan_value \
            LWBS_PLAN_MODULE_SERVICES \
            "$module_id" \
            "$service_requirement"

        service_key="$(
            execution_plan_service_key \
                "$module_id" \
                "$service_name"
        )"

        if ! service_manager_available; then
            printf 'Error: module %s requires systemd service management, but systemd is unavailable.\n' \
                "$module_id" >&2
            return 1
        fi

        if presence="$(query_service_presence "$service_name")"; then
            :
        else
            exit_code=$?
            return "$exit_code"
        fi

        if [[ "$presence" == "absent" ]]; then
            if "$has_planned_changes"; then
                LWBS_PLAN_SERVICE_ACTIONS["$service_key"]="deferred"
                ((LWBS_PLAN_SERVICE_ACTION_COUNT += 1))

                log_info \
                    "Service plan: module=$module_id service=$service_name action=deferred"

                continue
            fi

            printf 'Error: required service is unavailable: %s\n' \
                "$service_name" >&2

            log_error \
                "Required service unavailable during planning: module=$module_id service=$service_name"

            return 1
        fi

        planned_actions=()

        if [[ "$enabled_state" != "unchanged" ]]; then
            if current_enabled="$(query_service_enabled_state "$service_name")"; then
                :
            else
                exit_code=$?
                return "$exit_code"
            fi

            if [[ "$current_enabled" != "$enabled_state" ]]; then
                if [[ "$enabled_state" == "enabled" ]]; then
                    planned_actions+=("enable")
                else
                    planned_actions+=("disable")
                fi
            fi
        fi

        if [[ "$active_state" != "unchanged" ]]; then
            if current_active="$(query_service_active_state "$service_name")"; then
                :
            else
                exit_code=$?
                return "$exit_code"
            fi

            if [[ "$current_active" != "$active_state" ]]; then
                if [[ "$active_state" == "active" ]]; then
                    planned_actions+=("start")
                else
                    planned_actions+=("stop")
                fi
            elif [[ "$restart_policy" == "on-change" &&
                "$active_state" == "active" &&
                "$has_planned_changes" == "true" ]]; then

                planned_actions+=("restart")
            fi
        fi

        if ((${#planned_actions[@]} == 0)); then
            LWBS_PLAN_SERVICE_ACTIONS["$service_key"]="skip"
            ((LWBS_PLAN_SKIP_ACTION_COUNT += 1))

            log_info \
                "Service plan: module=$module_id service=$service_name action=skip"

            continue
        fi

        planned_action="$(
            IFS=,
            printf '%s' "${planned_actions[*]}"
        )"

        LWBS_PLAN_SERVICE_ACTIONS["$service_key"]="$planned_action"
        ((LWBS_PLAN_SERVICE_ACTION_COUNT += ${#planned_actions[@]}))

        log_info \
            "Service plan: module=$module_id service=$service_name action=$planned_action"
    done

    return 0
}

show_module_service_plan() {
    local module_id="${1:-}"
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy
    local service_key
    local action

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

        action="${LWBS_PLAN_SERVICE_ACTIONS[$service_key]:-skip}"

        case "$action" in
            skip)
                printf '  Service       : %s [state satisfied, skip]\n' \
                    "$service_name"
                ;;
            deferred)
                printf '  Service       : %s [configure after install: enabled=%s active=%s]\n' \
                    "$service_name" \
                    "$enabled_state" \
                    "$active_state"
                ;;
            *)
                printf '  Service       : %s [%s]\n' \
                    "$service_name" \
                    "$action"
                ;;
        esac
    done <<<"${LWBS_PLAN_MODULE_SERVICES[$module_id]:-}"
}

execute_planned_service_actions() {
    local module_id="${1:-}"
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy
    local service_key
    local result_key
    local planned_action
    local presence
    local current_state
    local exit_code
    local verification_exit_code
    local action_performed=false
    local started=false
    local execution_changed=false

    if module_execution_changed "$module_id"; then
        execution_changed=true
    fi

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

        result_key="$(
            service_result_key \
                "$module_id" \
                "$service_name"
        )"

        planned_action="${LWBS_PLAN_SERVICE_ACTIONS[$service_key]:-skip}"

        if ! service_manager_available; then
            record_execution_result \
                "$result_key" \
                "service" \
                "$module_id" \
                "$service_name" \
                "failed" \
                "systemd service management unavailable"
            return 1
        fi

        if presence="$(query_service_presence "$service_name")"; then
            :
        else
            record_execution_result \
                "$result_key" \
                "service" \
                "$module_id" \
                "$service_name" \
                "unverifiable" \
                "service presence check failed"
            return 1
        fi

        if [[ "$presence" != "present" ]]; then
            record_execution_result \
                "$result_key" \
                "service" \
                "$module_id" \
                "$service_name" \
                "failed" \
                "required service unavailable"
            return 1
        fi

        if [[ "$planned_action" == "skip" ]]; then
            if service_requirement_is_satisfied \
                "$service_name" \
                "$enabled_state" \
                "$active_state"; then

                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "skipped" \
                    "required service state already satisfied"
                continue
            fi

            verification_exit_code=$?

            if ((verification_exit_code == 1)); then
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "failed" \
                    "planned service state changed"
            else
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "unverifiable" \
                    "service state check failed"
            fi

            return 1
        fi

        action_performed=false
        started=false

        if [[ "$enabled_state" != "unchanged" ]]; then
            if current_state="$(query_service_enabled_state "$service_name")"; then
                :
            else
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "unverifiable" \
                    "enabled-state check failed"
                return 1
            fi

            if [[ "$current_state" != "$enabled_state" ]]; then
                if [[ "$enabled_state" == "enabled" ]]; then
                    if service_enable "$service_name"; then
                        action_performed=true
                    else
                        exit_code=$?
                        record_execution_result \
                            "$result_key" \
                            "service" \
                            "$module_id" \
                            "$service_name" \
                            "failed" \
                            "service enable failed"
                        return "$exit_code"
                    fi
                else
                    if service_disable "$service_name"; then
                        action_performed=true
                    else
                        exit_code=$?
                        record_execution_result \
                            "$result_key" \
                            "service" \
                            "$module_id" \
                            "$service_name" \
                            "failed" \
                            "service disable failed"
                        return "$exit_code"
                    fi
                fi
            fi
        fi

        if [[ "$active_state" != "unchanged" ]]; then
            if current_state="$(query_service_active_state "$service_name")"; then
                :
            else
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "unverifiable" \
                    "active-state check failed"
                return 1
            fi

            if [[ "$current_state" != "$active_state" ]]; then
                if [[ "$active_state" == "active" ]]; then
                    if service_start "$service_name"; then
                        action_performed=true
                        started=true
                    else
                        exit_code=$?
                        record_execution_result \
                            "$result_key" \
                            "service" \
                            "$module_id" \
                            "$service_name" \
                            "failed" \
                            "service start failed"
                        return "$exit_code"
                    fi
                else
                    if service_stop "$service_name"; then
                        action_performed=true
                    else
                        exit_code=$?
                        record_execution_result \
                            "$result_key" \
                            "service" \
                            "$module_id" \
                            "$service_name" \
                            "failed" \
                            "service stop failed"
                        return "$exit_code"
                    fi
                fi
            fi
        fi

        if [[ "$restart_policy" == "on-change" &&
            "$execution_changed" == "true" &&
            "$active_state" == "active" &&
            "$started" == "false" ]]; then

            if current_state="$(query_service_active_state "$service_name")"; then
                :
            else
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "unverifiable" \
                    "restart state check failed"
                return 1
            fi

            if [[ "$current_state" == "active" ]]; then
                if service_restart "$service_name"; then
                    action_performed=true
                else
                    exit_code=$?
                    record_execution_result \
                        "$result_key" \
                        "service" \
                        "$module_id" \
                        "$service_name" \
                        "failed" \
                        "service restart failed"
                    return "$exit_code"
                fi
            fi
        fi

        if service_requirement_is_satisfied \
            "$service_name" \
            "$enabled_state" \
            "$active_state"; then

            if "$action_performed"; then
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "successful" \
                    "required service state verified"
            else
                record_execution_result \
                    "$result_key" \
                    "service" \
                    "$module_id" \
                    "$service_name" \
                    "skipped" \
                    "planned service action no longer required"
            fi

            continue
        fi

        verification_exit_code=$?

        if ((verification_exit_code == 1)); then
            record_execution_result \
                "$result_key" \
                "service" \
                "$module_id" \
                "$service_name" \
                "failed" \
                "required service state not reached"
        else
            record_execution_result \
                "$result_key" \
                "service" \
                "$module_id" \
                "$service_name" \
                "unverifiable" \
                "post-action service state check failed"
        fi

        return 1
    done <<<"${LWBS_PLAN_MODULE_SERVICES[$module_id]:-}"

    return 0
}

record_skipped_service_results() {
    local module_id="${1:-}"
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy
    local result_key

    while IFS= read -r service_requirement; do
        [[ -z "$service_requirement" ]] && continue

        parse_service_requirement \
            "$service_requirement" \
            service_name \
            enabled_state \
            active_state \
            restart_policy

        result_key="$(
            service_result_key \
                "$module_id" \
                "$service_name"
        )"

        record_execution_result \
            "$result_key" \
            "service" \
            "$module_id" \
            "$service_name" \
            "skipped" \
            "required service state already satisfied"
    done <<<"${LWBS_PLAN_MODULE_SERVICES[$module_id]:-}"
}

reset_service_execution_plan() {
    LWBS_PLAN_SERVICE_ACTION_COUNT=0
    LWBS_PLAN_MODULE_SERVICES=()
    LWBS_PLAN_SERVICE_ACTIONS=()
}
