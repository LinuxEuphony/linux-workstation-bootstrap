#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Execution planning utilities.
# Resolves a workstation profile into a complete, reviewable execution plan
# before any system-changing operation is allowed to run.
#
# This file:
# 1. Resolves profile modules before execution.
# 2. Resolves module capabilities into distro-specific packages.
# 3. Evaluates package installation state.
# 4. Resolves declarative external software requirements.
# 5. Evaluates external software installation state.
# 6. Records custom module operation hooks.
# 7. Displays and logs the resolved plan.
# 8. Requires confirmation before applying changes.
# 9. Prevents dry-run mode from executing the resolved plan.
# 10. Detects important state drift before execution.

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

# Append one value to a newline-delimited associative-array entry.
append_execution_plan_value() {
    local map_name="${1:-}"
    local key="${2:-}"
    local value="${3:-}"

    if [[ -z "$map_name" || -z "$key" || -z "$value" ]]; then
        printf 'Error: incomplete execution-plan list append request.\n' >&2
        return 2
    fi

    local -n plan_map_ref="$map_name"

    if [[ -n "${plan_map_ref[$key]:-}" ]]; then
        plan_map_ref["$key"]+=$'\n'"$value"
    else
        plan_map_ref["$key"]="$value"
    fi
}

# Build the associative-array key used for one module/external pair.
execution_plan_external_key() {
    local module_id="${1:-}"
    local installer_id="${2:-}"

    printf '%s::%s\n' \
        "$module_id" \
        "$installer_id"
}

# Resolve a workstation profile into a complete execution plan.
build_profile_execution_plan() {
    local requested_profile="${1:-}"
    local module_id
    local module_name_value
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

        log_error \
            "Execution plan requested without a workstation profile."

        LWBS_PLAN_STATUS="invalid"
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ]]; then
        printf 'Error: a distribution adapter must be loaded before building an execution plan.\n' \
            >&2

        log_error \
            "Execution plan requested without a distribution adapter."

        LWBS_PLAN_STATUS="invalid"
        return 1
    fi

    if [[ -z "${LWBS_CAPABILITY_PROFILE:-}" ]]; then
        printf 'Error: a capability mapping must be loaded before building an execution plan.\n' \
            >&2

        log_error \
            "Execution plan requested without a capability mapping."

        LWBS_PLAN_STATUS="invalid"
        return 1
    fi

    if [[ "$LWBS_CAPABILITY_PROFILE" != "$DISTRO_ADAPTER_PROFILE" ]]; then
        printf 'Error: capability mapping profile "%s" does not match distribution adapter "%s".\n' \
            "$LWBS_CAPABILITY_PROFILE" \
            "$DISTRO_ADAPTER_PROFILE" >&2

        log_error \
            "Execution plan capability/distro mismatch: capability_profile=$LWBS_CAPABILITY_PROFILE adapter_profile=$DISTRO_ADAPTER_PROFILE"

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

            log_error \
                "Duplicate module detected while building execution plan: profile=$LWBS_PLAN_PROFILE_ID module=$module_id"

            reset_module_contract
            reset_profile_contract
            LWBS_PLAN_STATUS="invalid"
            return 1
        fi

        seen_modules["$module_id"]=1

        if load_module "$module_id"; then
            :
        else
            exit_code=$?

            reset_profile_contract
            LWBS_PLAN_STATUS="invalid"
            return "$exit_code"
        fi

        module_name_value="$LWBS_MODULE_NAME"
        LWBS_PLAN_MODULE_NAMES["$module_id"]="$module_name_value"

        resolved_packages=()

        if ((${#LWBS_MODULE_CAPABILITIES[@]} > 0)); then
            if resolve_capabilities \
                resolved_packages \
                "${LWBS_MODULE_CAPABILITIES[@]}"; then
                :
            else
                exit_code=$?

                reset_module_contract
                reset_profile_contract
                LWBS_PLAN_STATUS="invalid"
                return "$exit_code"
            fi

            for package in "${resolved_packages[@]}"; do
                if package_state="$(distro_package_state "$package")"; then
                    :
                else
                    exit_code=$?

                    printf 'Error: unable to determine package state while building plan: %s\n' \
                        "$package" >&2

                    log_error \
                        "Execution plan package state check failed: module=$module_id package=$package exit_code=$exit_code"

                    reset_module_contract
                    reset_profile_contract
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
                        printf 'Error: invalid package state "%s" while planning package %s.\n' \
                            "$package_state" \
                            "$package" >&2

                        log_error \
                            "Invalid package state while building execution plan: module=$module_id package=$package state=$package_state"

                        reset_module_contract
                        reset_profile_contract
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
                reset_profile_contract
                LWBS_PLAN_STATUS="invalid"
                return "$exit_code"
            fi

            if installer_state="$(query_external_installation_state)"; then
                :
            else
                exit_code=$?

                reset_external_installer_contract
                reset_module_contract
                reset_profile_contract
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

                *)
                    printf 'Error: invalid external software state "%s" while planning %s.\n' \
                        "$installer_state" \
                        "$installer_id" >&2

                    reset_external_installer_contract
                    reset_module_contract
                    reset_profile_contract
                    LWBS_PLAN_STATUS="invalid"
                    return 1
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

        reset_module_contract
    done

    # The resolved plan owns everything needed from the profile from here on.
    reset_profile_contract

    LWBS_PLAN_STATUS="resolved"

    log_execution_plan

    return 0
}

# Log the resolved plan without logging arbitrary installer arguments or URLs.
log_execution_plan() {
    local module_id
    local package
    local installer_id
    local external_key
    local action

    if [[ "$LWBS_PLAN_STATUS" != "resolved" ]]; then
        printf 'Error: execution plan must be resolved before it can be logged.\n' \
            >&2
        return 2
    fi

    log_info \
        "Execution plan resolved: profile=$LWBS_PLAN_PROFILE_ID distro=$LWBS_PLAN_DISTRO_PROFILE modules=${#LWBS_PLAN_MODULES[@]} install_actions=$LWBS_PLAN_INSTALL_ACTION_COUNT skip_actions=$LWBS_PLAN_SKIP_ACTION_COUNT custom_actions=$LWBS_PLAN_CUSTOM_ACTION_COUNT"

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        log_info \
            "Execution plan module: profile=$LWBS_PLAN_PROFILE_ID module=$module_id"

        while IFS= read -r package; do
            [[ -z "$package" ]] && continue

            log_info \
                "Execution plan package: module=$module_id package=$package action=install"
        done <<<"${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}"

        while IFS= read -r package; do
            [[ -z "$package" ]] && continue

            log_info \
                "Execution plan package: module=$module_id package=$package action=skip"
        done <<<"${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]:-}"

        while IFS= read -r installer_id; do
            [[ -z "$installer_id" ]] && continue

            external_key="$(
                execution_plan_external_key \
                    "$module_id" \
                    "$installer_id"
            )"

            action="${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-unknown}"

            log_info \
                "Execution plan external software: module=$module_id installer=$installer_id action=$action"
        done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"

        if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" == "true" ]]; then
            log_info \
                "Execution plan custom module operation: module=$module_id action=apply"
        fi
    done
}

# Display the complete resolved plan.
show_execution_plan() {
    local module_id
    local package
    local installer_id
    local external_key
    local action
    local has_package_entries
    local has_external_entries

    case "$LWBS_PLAN_STATUS" in
        resolved | approved | previewed)
            ;;
        *)
            printf 'Error: no resolved execution plan is available for display.\n' \
                >&2
            return 2
            ;;
    esac

    printf '\nExecution plan\n\n'
    printf '  Profile      : %s (%s)\n' \
        "$LWBS_PLAN_PROFILE_NAME" \
        "$LWBS_PLAN_PROFILE_ID"

    printf '  Distribution : %s\n' \
        "$(distro_profile_name "$LWBS_PLAN_DISTRO_PROFILE")"

    printf '  Modules      : %d\n' \
        "${#LWBS_PLAN_MODULES[@]}"

    printf '\n'

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        printf 'Module: %s\n' \
            "${LWBS_PLAN_MODULE_NAMES[$module_id]:-$module_id}"

        printf '  ID           : %s\n' "$module_id"

        has_package_entries=false

        if [[ -n "${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]:-}" ]]; then
            if ! "$has_package_entries"; then
                printf '  Packages:\n'
                has_package_entries=true
            fi

            while IFS= read -r package; do
                [[ -z "$package" ]] && continue

                printf '    - %s [installed, skip]\n' \
                    "$package"
            done <<<"${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]}"
        fi

        if [[ -n "${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}" ]]; then
            if ! "$has_package_entries"; then
                printf '  Packages:\n'
                has_package_entries=true
            fi

            while IFS= read -r package; do
                [[ -z "$package" ]] && continue

                printf '    - %s [install]\n' \
                    "$package"
            done <<<"${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]}"
        fi

        if ! "$has_package_entries"; then
            printf '  Packages     : none\n'
        fi

        has_external_entries=false

        if [[ -n "${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}" ]]; then
            printf '  External software:\n'
            has_external_entries=true

            while IFS= read -r installer_id; do
                [[ -z "$installer_id" ]] && continue

                external_key="$(
                    execution_plan_external_key \
                        "$module_id" \
                        "$installer_id"
                )"

                action="${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-unknown}"

                case "$action" in
                    install)
                        printf '    - %s [install]\n' "$installer_id"
                        ;;
                    skip)
                        printf '    - %s [installed, skip]\n' "$installer_id"
                        ;;
                    *)
                        printf '    - %s [unknown]\n' "$installer_id"
                        ;;
                esac
            done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]}"
        fi

        if ! "$has_external_entries"; then
            printf '  External     : none\n'
        fi

        if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" == "true" ]]; then
            printf '  Custom action: module_apply\n'
        fi

        printf '\n'
    done

    printf 'Plan summary\n\n'
    printf '  Install actions : %d\n' "$LWBS_PLAN_INSTALL_ACTION_COUNT"
    printf '  Skipped actions : %d\n' "$LWBS_PLAN_SKIP_ACTION_COUNT"
    printf '  Custom actions  : %d\n' "$LWBS_PLAN_CUSTOM_ACTION_COUNT"
    printf '\n'
}

# Return success when the current plan would modify the workstation.
execution_plan_has_changes() {
    if ((LWBS_PLAN_INSTALL_ACTION_COUNT > 0 ||
        LWBS_PLAN_CUSTOM_ACTION_COUNT > 0)); then
        return 0
    fi

    return 1
}

# Ensure packages that were approved as already satisfied have not become
# absent between plan creation and execution.
verify_planned_skipped_packages() {
    local module_id="${1:-}"
    local package
    local package_state
    local exit_code

    while IFS= read -r package; do
        [[ -z "$package" ]] && continue

        if package_state="$(distro_package_state "$package")"; then
            :
        else
            exit_code=$?

            printf 'Error: unable to revalidate planned package state: %s\n' \
                "$package" >&2

            return "$exit_code"
        fi

        if [[ "$package_state" != "installed" ]]; then
            printf 'Error: execution plan is stale. Package "%s" was planned as installed but is now absent.\n' \
                "$package" >&2

            log_error \
                "Execution plan drift detected: module=$module_id package=$package expected=installed actual=$package_state"

            return 1
        fi
    done <<<"${LWBS_PLAN_MODULE_SKIP_PACKAGES[$module_id]:-}"

    return 0
}

# Recheck packages approved for installation immediately before execution.
#
# Packages that became installed after planning are safely removed from the
# execution set. Packages that are still absent remain eligible for install.
collect_execution_packages() {
    local module_id="${1:-}"
    local result_name="${2:-}"
    local package
    local package_state
    local exit_code

    if [[ -z "$module_id" || -z "$result_name" ]]; then
        printf 'Error: incomplete execution-package collection request.\n' >&2
        return 2
    fi

    if [[ ! "$result_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'Error: invalid execution-package output array name: %s\n' \
            "$result_name" >&2
        return 2
    fi

    local -n execution_packages_ref="$result_name"

    execution_packages_ref=()

    while IFS= read -r package; do
        [[ -z "$package" ]] && continue

        if package_state="$(distro_package_state "$package")"; then
            :
        else
            exit_code=$?

            printf 'Error: unable to revalidate package before execution: %s\n' \
                "$package" >&2

            return "$exit_code"
        fi

        case "$package_state" in
            installed)
                log_info \
                    "Planned package became satisfied before execution: module=$module_id package=$package"
                ;;

            absent)
                execution_packages_ref+=("$package")
                ;;

            *)
                printf 'Error: invalid package state before execution: %s\n' \
                    "$package_state" >&2
                return 1
                ;;
        esac
    done <<<"${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}"

    return 0
}

# Execute the external software actions approved for one module.
execute_planned_external_actions() {
    local module_id="${1:-}"
    local installer_id
    local external_key
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

        action="${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-}"

        case "$action" in
            skip)
                if load_external_installer "$installer_id"; then
                    :
                else
                    exit_code=$?
                    return "$exit_code"
                fi

                if current_state="$(query_external_installation_state)"; then
                    :
                else
                    exit_code=$?
                    reset_external_installer_contract
                    return "$exit_code"
                fi

                reset_external_installer_contract

                if [[ "$current_state" != "installed" ]]; then
                    printf 'Error: execution plan is stale. External software "%s" was planned as installed but is now absent.\n' \
                        "$installer_id" >&2

                    log_error \
                        "Execution plan drift detected: module=$module_id installer=$installer_id expected=installed actual=$current_state"

                    return 1
                fi
                ;;

            install)
                if run_external_installer "$installer_id"; then
                    reset_external_installer_contract
                else
                    exit_code=$?
                    reset_external_installer_contract
                    return "$exit_code"
                fi
                ;;

            *)
                printf 'Error: invalid planned external action for %s: %s\n' \
                    "$installer_id" \
                    "$action" >&2
                return 1
                ;;
        esac
    done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"

    return 0
}

# Execute the custom operation explicitly recorded for one module.
execute_planned_module_apply() {
    local module_id="${1:-}"
    local exit_code

    if [[ "${LWBS_PLAN_MODULE_HAS_APPLY[$module_id]:-false}" != "true" ]]; then
        return 0
    fi

    if load_module "$module_id"; then
        :
    else
        return $?
    fi

    if ! declare -F module_apply >/dev/null 2>&1; then
        printf 'Error: execution plan is stale. Module "%s" no longer provides module_apply.\n' \
            "$module_id" >&2

        reset_module_contract
        return 1
    fi

    log_info \
        "Executing approved custom module action: module=$module_id"

    if module_apply; then
        reset_module_contract
        return 0
    else
        exit_code=$?
        reset_module_contract
        return "$exit_code"
    fi
}

# Execute a previously resolved and approved plan.
execute_resolved_plan() {
    local module_id
    local exit_code

    local -a execution_packages=()

    if [[ "$LWBS_PLAN_STATUS" != "approved" ]]; then
        printf 'Error: execution plan must be approved before execution.\n' >&2

        log_error \
            "Execution attempted without approved plan: status=$LWBS_PLAN_STATUS"

        return 1
    fi

    LWBS_PLAN_STATUS="executing"

    log_info \
        "Execution plan started: profile=$LWBS_PLAN_PROFILE_ID"

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        if verify_planned_skipped_packages "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            return "$exit_code"
        fi

        execution_packages=()

        if collect_execution_packages \
            "$module_id" \
            execution_packages; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            return "$exit_code"
        fi

        if ((${#execution_packages[@]} > 0)); then
            log_info \
                "Executing approved package installation: module=$module_id count=${#execution_packages[@]}"

            if distro_install_packages "${execution_packages[@]}"; then
                :
            else
                exit_code=$?
                LWBS_PLAN_STATUS="failed"
                return "$exit_code"
            fi
        fi

        if execute_planned_external_actions "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            return "$exit_code"
        fi

        if execute_planned_module_apply "$module_id"; then
            :
        else
            exit_code=$?
            LWBS_PLAN_STATUS="failed"
            return "$exit_code"
        fi
    done

    LWBS_PLAN_STATUS="completed"

    log_info \
        "Execution plan completed successfully: profile=$LWBS_PLAN_PROFILE_ID"

    return 0
}

# Resolve, display, approve, and execute one workstation profile.
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

        log_info \
            "Execution plan previewed without execution: profile=$LWBS_PLAN_PROFILE_ID"

        return 0
    fi

    if ! execution_plan_has_changes; then
        LWBS_PLAN_STATUS="completed"

        printf 'No system changes are required. All planned requirements are already satisfied.\n'

        log_info \
            "Execution plan requires no changes: profile=$LWBS_PLAN_PROFILE_ID"

        return 0
    fi

    if confirm_execution_plan; then
        LWBS_PLAN_STATUS="approved"

        log_info \
            "Execution plan approved: profile=$LWBS_PLAN_PROFILE_ID"
    else
        confirmation_exit_code=$?

        if ((confirmation_exit_code == 1)); then
            LWBS_PLAN_STATUS="cancelled"

            printf '\nExecution cancelled. No planned changes were applied.\n'

            log_info \
                "Execution plan cancelled by user: profile=$LWBS_PLAN_PROFILE_ID"

            return 0
        fi

        LWBS_PLAN_STATUS="unapproved"

        log_error \
            "Execution plan could not be approved: profile=$LWBS_PLAN_PROFILE_ID exit_code=$confirmation_exit_code"

        return "$confirmation_exit_code"
    fi

    if execute_resolved_plan; then
        return 0
    else
        exit_code=$?
        return "$exit_code"
    fi
}

# Clear all execution-plan state.
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
}