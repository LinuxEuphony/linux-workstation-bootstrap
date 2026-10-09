#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Execution planning, controlled execution, and post-install verification.
#
# A profile is fully resolved before modification. Approved actions are then
# executed and verified before a final result is reported.

LWBS_PLAN_STATUS="empty"

LWBS_PLAN_PROFILE_ID=""
LWBS_PLAN_PROFILE_NAME=""
LWBS_PLAN_PROFILE_DESCRIPTION=""
LWBS_PLAN_DISTRO_PROFILE=""

LWBS_PLAN_INSTALL_ACTION_COUNT=0
LWBS_PLAN_SKIP_ACTION_COUNT=0
LWBS_PLAN_CUSTOM_ACTION_COUNT=0

declare -a LWBS_PLAN_MODULES=()

declare -A LWBS_PLAN_MODULE_NAMES=()
declare -A LWBS_PLAN_MODULE_INSTALL_PACKAGES=()
declare -A LWBS_PLAN_MODULE_SKIP_PACKAGES=()
declare -A LWBS_PLAN_MODULE_EXTERNALS=()
declare -A LWBS_PLAN_EXTERNAL_ACTIONS=()
declare -A LWBS_PLAN_MODULE_HAS_APPLY=()
declare -A LWBS_PLAN_MODULE_HAS_VERIFY=()

append_execution_plan_value() {
    local map_name="${1:-}"
    local key="${2:-}"
    local value="${3:-}"

    local -n plan_map_ref="$map_name"

    if [[ -n "${plan_map_ref[$key]:-}" ]]; then
        plan_map_ref["$key"]+=$'\n'"$value"
    else
        plan_map_ref["$key"]="$value"
    fi
}

execution_plan_external_key() {
    printf '%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

build_profile_execution_plan() {
    local requested_profile="${1:-}"
    local module_id
    local package
    local package_state
    local installer_id
    local installer_state
    local external_key
    local exit_code

    local -a resolved_packages=()
    local -A seen_modules=()

    reset_execution_plan
    LWBS_PLAN_STATUS="building"

    if [[ -z "$requested_profile" ]]; then
        printf 'Error: no workstation profile was provided for execution planning.\n' \
            >&2
        LWBS_PLAN_STATUS="invalid"
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ||
        -z "${LWBS_CAPABILITY_PROFILE:-}" ]]; then

        printf 'Error: distro adapter and capability mapping must be loaded before planning.\n' \
            >&2

        LWBS_PLAN_STATUS="invalid"
        return 1
    fi

    if load_profile "$requested_profile"; then
        :
    else
        exit_code=$?
        LWBS_PLAN_STATUS="invalid"
        return "$exit_code"
    fi

    LWBS_PLAN_PROFILE_ID="$LWBS_PROFILE_ID"
    LWBS_PLAN_PROFILE_NAME="$LWBS_PROFILE_NAME"
    LWBS_PLAN_PROFILE_DESCRIPTION="$LWBS_PROFILE_DESCRIPTION"
    LWBS_PLAN_DISTRO_PROFILE="$DISTRO_ADAPTER_PROFILE"
    LWBS_PLAN_MODULES=("${LWBS_PROFILE_MODULES[@]}")

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        if [[ -n "${seen_modules[$module_id]+defined}" ]]; then
            printf 'Error: execution plan contains duplicate module: %s\n' \
                "$module_id" >&2

            LWBS_PLAN_STATUS="invalid"
            return 1
        fi

        seen_modules["$module_id"]=1

        if load_module "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="invalid"
            return "$exit_code"
        fi

        LWBS_PLAN_MODULE_NAMES["$module_id"]="$LWBS_MODULE_NAME"

        resolved_packages=()

        if ((${#LWBS_MODULE_CAPABILITIES[@]} > 0)); then
            if resolve_capabilities \
                resolved_packages \
                "${LWBS_MODULE_CAPABILITIES[@]}"; then
                :
            else
                exit_code=$?
                reset_module_contract
                LWBS_PLAN_STATUS="invalid"
                return "$exit_code"
            fi

            for package in "${resolved_packages[@]}"; do
                if package_state="$(distro_package_state "$package")"; then
                    :
                else
                    exit_code=$?
                    reset_module_contract
                    LWBS_PLAN_STATUS="invalid"
                    return "$exit_code"
                fi

                case "$package_state" in
                    installed)
                        append_execution_plan_value \
                            LWBS_PLAN_MODULE_SKIP_PACKAGES \
                            "$module_id" \
                            "$package"

                        ((LWBS_PLAN_SKIP_ACTION_COUNT += 1))
                        ;;

                    absent)
                        append_execution_plan_value \
                            LWBS_PLAN_MODULE_INSTALL_PACKAGES \
                            "$module_id" \
                            "$package"

                        ((LWBS_PLAN_INSTALL_ACTION_COUNT += 1))
                        ;;

                    *)
                        reset_module_contract
                        LWBS_PLAN_STATUS="invalid"
                        return 1
                        ;;
                esac
            done
        fi

        for installer_id in "${LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"; do
            if load_external_installer "$installer_id"; then
                :
            else
                exit_code=$?
                reset_module_contract
                LWBS_PLAN_STATUS="invalid"
                return "$exit_code"
            fi

            if installer_state="$(query_external_installation_state)"; then
                :
            else
                exit_code=$?
                reset_external_installer_contract
                reset_module_contract
                LWBS_PLAN_STATUS="invalid"
                return "$exit_code"
            fi

            append_execution_plan_value \
                LWBS_PLAN_MODULE_EXTERNALS \
                "$module_id" \
                "$installer_id"

            external_key="$(
                execution_plan_external_key \
                    "$module_id" \
                    "$installer_id"
            )"

            case "$installer_state" in
                installed)
                    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="skip"
                    ((LWBS_PLAN_SKIP_ACTION_COUNT += 1))
                    ;;
                absent)
                    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="install"
                    ((LWBS_PLAN_INSTALL_ACTION_COUNT += 1))
                    ;;
            esac

            reset_external_installer_contract
        done

        if declare -F module_apply >/dev/null 2>&1; then
            LWBS_PLAN_MODULE_HAS_APPLY["$module_id"]="true"
            ((LWBS_PLAN_CUSTOM_ACTION_COUNT += 1))
        else
            LWBS_PLAN_MODULE_HAS_APPLY["$module_id"]="false"
        fi

        if declare -F module_verify >/dev/null 2>&1; then
            LWBS_PLAN_MODULE_HAS_VERIFY["$module_id"]="true"
        else
            LWBS_PLAN_MODULE_HAS_VERIFY["$module_id"]="false"
        fi

        reset_module_contract
    done

    reset_profile_contract

    LWBS_PLAN_STATUS="resolved"

    log_execution_plan

    return 0
}

log_execution_plan() {
    log_info \
        "Execution plan resolved: profile=$LWBS_PLAN_PROFILE_ID distro=$LWBS_PLAN_DISTRO_PROFILE modules=${#LWBS_PLAN_MODULES[@]} install_actions=$LWBS_PLAN_INSTALL_ACTION_COUNT skip_actions=$LWBS_PLAN_SKIP_ACTION_COUNT custom_actions=$LWBS_PLAN_CUSTOM_ACTION_COUNT"
}

show_execution_plan() {
    local module_id
    local package
    local installer_id
    local external_key
    local action

    printf '\nExecution plan\n\n'

    printf '  Profile      : %s (%s)\n' \
        "$LWBS_PLAN_PROFILE_NAME" \
        "$LWBS_PLAN_PROFILE_ID"

    printf '  Distribution : %s\n' \
        "$(distro_profile_name "$LWBS_PLAN_DISTRO_PROFILE")"

    printf '  Modules      : %d\n\n' \
        "${#LWBS_PLAN_MODULES[@]}"

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        printf 'Module: %s\n' \
            "${LWBS_PLAN_MODULE_NAMES[$module_id]:-$module_id}"

        while IFS= read -r package; do
            [[ -z "$package" ]] && continue
            printf '  Package      : %s [installed, skip]\n' "$package"
        done <<<"${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]:-}"

        while IFS= read -r package; do
            [[ -z "$package" ]] && continue
            printf '  Package      : %s [install]\n' "$package"
        done <<<"${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}"

        while IFS= read -r installer_id; do
            [[ -z "$installer_id" ]] && continue

            external_key="$(
                execution_plan_external_key \
                    "$module_id" \
                    "$installer_id"
            )"

            action="${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]}"

            if [[ "$action" == "skip" ]]; then
                printf '  External     : %s [installed, skip]\n' "$installer_id"
            else
                printf '  External     : %s [install]\n' "$installer_id"
            fi
        done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"

        if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" == "true" ]]; then
            printf '  Custom action: module_apply\n'
        fi

        if [[ "${LWBS_PLAN_MODULE_HAS_VERIFY[$module_id]:-false}" == "true" ]]; then
            printf '  Post-check   : module_verify\n'
        fi

        printf '\n'
    done
}

execution_plan_has_changes() {
    ((LWBS_PLAN_INSTALL_ACTION_COUNT > 0 ||
        LWBS_PLAN_CUSTOM_ACTION_COUNT > 0))
}

execute_planned_packages() {
    local module_id="${1:-}"
    local package
    local package_state
    local result_key
    local exit_code
    local verification_failed=false

    local -a packages_to_install=()

    while IFS= read -r package; do
        [[ -z "$package" ]] && continue

        result_key="$(package_result_key "$module_id" "$package")"

        if package_state="$(distro_package_state "$package")"; then
            :
        else
            record_execution_result \
                "$result_key" \
                "package" \
                "$module_id" \
                "$package" \
                "unverifiable" \
                "state check failed"

            return 1
        fi

        if [[ "$package_state" != "installed" ]]; then
            record_execution_result \
                "$result_key" \
                "package" \
                "$module_id" \
                "$package" \
                "failed" \
                "planned installed state changed"

            return 1
        fi

        record_execution_result \
            "$result_key" \
            "package" \
            "$module_id" \
            "$package" \
            "skipped" \
            "already installed"

    done <<<"${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]:-}"

    while IFS= read -r package; do
        [[ -z "$package" ]] && continue

        if package_state="$(distro_package_state "$package")"; then
            :
        else
            result_key="$(package_result_key "$module_id" "$package")"

            record_execution_result \
                "$result_key" \
                "package" \
                "$module_id" \
                "$package" \
                "unverifiable" \
                "pre-install state check failed"

            return 1
        fi

        case "$package_state" in
            installed)
                result_key="$(package_result_key "$module_id" "$package")"

                record_execution_result \
                    "$result_key" \
                    "package" \
                    "$module_id" \
                    "$package" \
                    "skipped" \
                    "became installed before execution"
                ;;

            absent)
                packages_to_install+=("$package")
                ;;

            *)
                return 1
                ;;
        esac
    done <<<"${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}"

    if ((${#packages_to_install[@]} == 0)); then
        return 0
    fi

    if distro_install_packages "${packages_to_install[@]}"; then
        :
    else
        exit_code=$?

        for package in "${packages_to_install[@]}"; do
            result_key="$(package_result_key "$module_id" "$package")"

            record_execution_result \
                "$result_key" \
                "package" \
                "$module_id" \
                "$package" \
                "failed" \
                "package installation command failed"
        done

        return "$exit_code"
    fi

    for package in "${packages_to_install[@]}"; do
        result_key="$(package_result_key "$module_id" "$package")"

        if package_state="$(distro_package_state "$package")"; then
            case "$package_state" in
                installed)
                    record_execution_result \
                        "$result_key" \
                        "package" \
                        "$module_id" \
                        "$package" \
                        "successful" \
                        "verified installed"
                    ;;

                absent)
                    record_execution_result \
                        "$result_key" \
                        "package" \
                        "$module_id" \
                        "$package" \
                        "failed" \
                        "package remained absent after installation"

                    verification_failed=true
                    ;;
            esac
        else
            record_execution_result \
                "$result_key" \
                "package" \
                "$module_id" \
                "$package" \
                "unverifiable" \
                "post-install state check failed"

            verification_failed=true
        fi
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}

execute_planned_external_actions() {
    local module_id="${1:-}"
    local installer_id
    local external_key
    local result_key
    local action
    local current_state
    local exit_code

    while IFS= read -r installer_id; do
        [[ -z "$installer_id" ]] && continue

        external_key="$(
            execution_plan_external_key \
                "$module_id" \
                "$installer_id"
        )"

        result_key="$(
            external_result_key \
                "$module_id" \
                "$installer_id"
        )"

        action="${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-}"

        if load_external_installer "$installer_id"; then
            :
        else
            record_execution_result \
                "$result_key" \
                "external" \
                "$module_id" \
                "$installer_id" \
                "failed" \
                "installer definition unavailable"

            return 1
        fi

        if current_state="$(query_external_installation_state)"; then
            :
        else
            reset_external_installer_contract

            record_execution_result \
                "$result_key" \
                "external" \
                "$module_id" \
                "$installer_id" \
                "unverifiable" \
                "state check failed"

            return 1
        fi

        if [[ "$action" == "skip" ]]; then
            if [[ "$current_state" == "installed" ]]; then
                record_execution_result \
                    "$result_key" \
                    "external" \
                    "$module_id" \
                    "$installer_id" \
                    "skipped" \
                    "already installed"

                reset_external_installer_contract
                continue
            fi

            record_execution_result \
                "$result_key" \
                "external" \
                "$module_id" \
                "$installer_id" \
                "failed" \
                "planned installed state changed"

            reset_external_installer_contract
            return 1
        fi

        if [[ "$current_state" == "installed" ]]; then
            record_execution_result \
                "$result_key" \
                "external" \
                "$module_id" \
                "$installer_id" \
                "skipped" \
                "became installed before execution"

            reset_external_installer_contract
            continue
        fi

        if execute_loaded_external_installer; then
            :
        else
            exit_code=$?

            record_execution_result \
                "$result_key" \
                "external" \
                "$module_id" \
                "$installer_id" \
                "failed" \
                "external installer failed"

            reset_external_installer_contract
            return "$exit_code"
        fi

        if current_state="$(query_external_installation_state)"; then
            if [[ "$current_state" == "installed" ]]; then
                record_execution_result \
                    "$result_key" \
                    "external" \
                    "$module_id" \
                    "$installer_id" \
                    "successful" \
                    "verified installed"

                reset_external_installer_contract
                continue
            fi

            record_execution_result \
                "$result_key" \
                "external" \
                "$module_id" \
                "$installer_id" \
                "failed" \
                "software remained absent after installation"

            reset_external_installer_contract
            return 1
        fi

        record_execution_result \
            "$result_key" \
            "external" \
            "$module_id" \
            "$installer_id" \
            "unverifiable" \
            "post-install state check failed"

        reset_external_installer_contract
        return 1
    done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"

    return 0
}

execute_and_verify_module_action() {
    local module_id="${1:-}"
    local result_key
    local exit_code

    local has_apply="${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}"
    local has_verify="${LWBS_PLAN_MODULE_HAS_VERIFY[$module_id]:-false}"

    if [[ "$has_apply" != "true" && "$has_verify" != "true" ]]; then
        return 0
    fi

    result_key="$(module_result_key "$module_id")"

    if load_module "$module_id"; then
        :
    else
        record_execution_result \
            "$result_key" \
            "module" \
            "$module_id" \
            "$module_id" \
            "failed" \
            "module could not be reloaded"

        return 1
    fi

    if [[ "$has_apply" == "true" ]]; then
        if module_apply; then
            :
        else
            exit_code=$?

            record_execution_result \
                "$result_key" \
                "module" \
                "$module_id" \
                "$module_id" \
                "failed" \
                "module_apply failed"

            reset_module_contract
            return "$exit_code"
        fi
    fi

    if [[ "$has_verify" == "true" ]]; then
        if module_verify; then
            record_execution_result \
                "$result_key" \
                "module" \
                "$module_id" \
                "$module_id" \
                "successful" \
                "module verification passed"

            reset_module_contract
            return 0
        fi

        exit_code=$?

        record_execution_result \
            "$result_key" \
            "module" \
            "$module_id" \
            "$module_id" \
            "failed" \
            "module verification failed"

        reset_module_contract
        return "$exit_code"
    fi

    record_execution_result \
        "$result_key" \
        "module" \
        "$module_id" \
        "$module_id" \
        "unverifiable" \
        "module has no verification hook"

    reset_module_contract

    return 0
}

execute_resolved_plan() {
    local module_id
    local exit_code

    if [[ "$LWBS_PLAN_STATUS" != "approved" ]]; then
        printf 'Error: execution plan must be approved before execution.\n' \
            >&2
        return 1
    fi

    reset_execution_results

    LWBS_PLAN_STATUS="executing"

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        if execute_planned_packages "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            show_execution_summary
            return "$exit_code"
        fi

        if execute_planned_external_actions "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            show_execution_summary
            return "$exit_code"
        fi

        if execute_and_verify_module_action "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            show_execution_summary
            return "$exit_code"
        fi
    done

    show_execution_summary

    if ! execution_results_are_successful; then
        LWBS_PLAN_STATUS="failed"
        return 1
    fi

    LWBS_PLAN_STATUS="completed"

    log_info \
        "Execution plan completed successfully: profile=$LWBS_PLAN_PROFILE_ID"

    return 0
}

run_profile_execution_plan() {
    local profile_id="${1:-}"
    local confirmation_exit_code
    local exit_code

    if build_profile_execution_plan "$profile_id"; then
        :
    else
        return $?
    fi

    show_execution_plan

    if "$LWBS_DRY_RUN"; then
        LWBS_PLAN_STATUS="previewed"

        printf 'Dry-run mode: execution plan was not applied.\n'

        return 0
    fi

    if ! execution_plan_has_changes; then
        reset_execution_results

        # Record actions that were already satisfied even when no execution
        # was required.
        local module_id
        local package
        local installer_id
        local result_key

        for module_id in "${LWBS_PLAN_MODULES[@]}"; do
            while IFS= read -r package; do
                [[ -z "$package" ]] && continue

                result_key="$(package_result_key "$module_id" "$package")"

                record_execution_result \
                    "$result_key" \
                    "package" \
                    "$module_id" \
                    "$package" \
                    "skipped" \
                    "already installed"
            done <<<"${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]:-}"

            while IFS= read -r installer_id; do
                [[ -z "$installer_id" ]] && continue

                result_key="$(
                    external_result_key \
                        "$module_id" \
                        "$installer_id"
                )"

                record_execution_result \
                    "$result_key" \
                    "external" \
                    "$module_id" \
                    "$installer_id" \
                    "skipped" \
                    "already installed"
            done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"
        done

        LWBS_PLAN_STATUS="completed"

        show_execution_summary

        return 0
    fi

    if confirm_execution_plan; then
        LWBS_PLAN_STATUS="approved"
    else
        confirmation_exit_code=$?

        if ((confirmation_exit_code == 1)); then
            LWBS_PLAN_STATUS="cancelled"
            printf '\nExecution cancelled. No planned changes were applied.\n'
            return 0
        fi

        return "$confirmation_exit_code"
    fi

    if execute_resolved_plan; then
        return 0
    else
        exit_code=$?
        return "$exit_code"
    fi
}

reset_execution_plan() {
    LWBS_PLAN_STATUS="empty"

    LWBS_PLAN_PROFILE_ID=""
    LWBS_PLAN_PROFILE_NAME=""
    LWBS_PLAN_PROFILE_DESCRIPTION=""
    LWBS_PLAN_DISTRO_PROFILE=""

    LWBS_PLAN_INSTALL_ACTION_COUNT=0
    LWBS_PLAN_SKIP_ACTION_COUNT=0
    LWBS_PLAN_CUSTOM_ACTION_COUNT=0

    LWBS_PLAN_MODULES=()

    LWBS_PLAN_MODULE_NAMES=()
    LWBS_PLAN_MODULE_INSTALL_PACKAGES=()
    LWBS_PLAN_MODULE_SKIP_PACKAGES=()
    LWBS_PLAN_MODULE_EXTERNALS=()
    LWBS_PLAN_EXTERNAL_ACTIONS=()
    LWBS_PLAN_MODULE_HAS_APPLY=()
    LWBS_PLAN_MODULE_HAS_VERIFY=()
}