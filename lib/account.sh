#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Managed workstation user and group membership support.
#
# Modules declare required group memberships without invoking usermod,
# gpasswd, or other account-management commands directly.
#
# The framework:
# 1. Resolves the workstation user independently from effective root access.
# 2. Checks existing users, groups, and memberships.
# 3. Plans only missing memberships.
# 4. Defers a missing group when the same module has installation work that
#    may create the group.
# 5. Routes account changes through shared privilege handling.
# 6. Records logout/login follow-up requirements after membership changes.
# 7. Never creates or removes users or groups implicitly.

LWBS_TARGET_USER=""
LWBS_TARGET_USER_SOURCE=""

LWBS_PLAN_ACCOUNT_ACTION_COUNT=0

declare -A LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS=()
declare -A LWBS_PLAN_GROUP_ACTIONS=()
declare -A LWBS_PLAN_GROUP_OWNERS=()

account_group_plan_key() {
    printf '%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

account_result_key() {
    printf 'group::%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

account_require_query_commands() {
    local command_name

    for command_name in id getent; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required account-management query command is unavailable: %s\n' \
            "$command_name" >&2

        return 1
    done

    return 0
}

account_user_exists() {
    local user_name="${1:-}"

    [[ -n "$user_name" ]] || return 1

    id -u "$user_name" >/dev/null 2>&1
}

account_group_exists() {
    local group_name="${1:-}"

    [[ -n "$group_name" ]] || return 1

    getent group "$group_name" >/dev/null 2>&1
}

account_user_in_group() {
    local user_name="${1:-}"
    local required_group="${2:-}"
    local groups
    local group_name

    if [[ -z "$user_name" || -z "$required_group" ]]; then
        return 2
    fi

    if groups="$(id -nG "$user_name" 2>/dev/null)"; then
        :
    else
        return 2
    fi

    for group_name in $groups; do
        if [[ "$group_name" == "$required_group" ]]; then
            return 0
        fi
    done

    return 1
}

initialize_target_workstation_user() {
    local candidate_user
    local source_name

    if ! account_require_query_commands; then
        return 1
    fi

    if [[ -n "${LWBS_TARGET_USER_OVERRIDE:-}" ]]; then
        candidate_user="$LWBS_TARGET_USER_OVERRIDE"
        source_name="override"

    elif [[ -n "${SUDO_USER:-}" &&
        "$SUDO_USER" != "root" ]]; then

        candidate_user="$SUDO_USER"
        source_name="sudo"

    else
        if candidate_user="$(id -un 2>/dev/null)"; then
            :
        else
            printf 'Error: unable to determine the target workstation user.\n' \
                >&2

            return 1
        fi

        source_name="effective-user"
    fi

    if [[ ! "$candidate_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid target workstation user: %s\n' \
            "$candidate_user" >&2

        return 1
    fi

    if ! account_user_exists "$candidate_user"; then
        printf 'Error: target workstation user does not exist: %s\n' \
            "$candidate_user" >&2

        return 1
    fi

    LWBS_TARGET_USER="$candidate_user"
    LWBS_TARGET_USER_SOURCE="$source_name"

    if [[ -n "${LWBS_LOG_FILE:-}" ]]; then
        log_info \
            "Target workstation user resolved: user=$LWBS_TARGET_USER source=$LWBS_TARGET_USER_SOURCE"
    fi

    return 0
}

account_usermod_command() {
    if command_exists usermod; then
        printf '%s\n' "usermod"
        return 0
    fi

    if [[ -x "/usr/sbin/usermod" ]]; then
        printf '%s\n' "/usr/sbin/usermod"
        return 0
    fi

    return 1
}

account_module_may_create_group() {
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

plan_module_group_memberships() {
    local module_id="${1:-}"
    local group_name
    local plan_key
    local existing_owner
    local membership_exit_code
    local exit_code

    if ((${#LWBS_MODULE_GROUP_MEMBERSHIPS[@]} == 0)); then
        return 0
    fi

    # bootstrap_main resolves this before normal execution, but planning is
    # also invoked directly by unit tests and reusable library callers.
    if [[ -z "$LWBS_TARGET_USER" ]]; then
        if initialize_target_workstation_user; then
            :
        else
            exit_code=$?
            return "$exit_code"
        fi
    fi

    if ! account_require_query_commands; then
        return 1
    fi

    if ! account_user_exists "$LWBS_TARGET_USER"; then
        printf 'Error: target workstation user no longer exists: %s\n' \
            "$LWBS_TARGET_USER" >&2

        return 1
    fi

    for group_name in "${LWBS_MODULE_GROUP_MEMBERSHIPS[@]}"; do
        append_execution_plan_value \
            LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS \
            "$module_id" \
            "$group_name"

        plan_key="$(
            account_group_plan_key \
                "$module_id" \
                "$group_name"
        )"

        existing_owner="${LWBS_PLAN_GROUP_OWNERS[$group_name]:-}"

        if [[ -n "$existing_owner" ]]; then
            LWBS_PLAN_GROUP_ACTIONS["$plan_key"]="shared"

            log_info \
                "Group membership plan shared: module=$module_id user=$LWBS_TARGET_USER group=$group_name owner=$existing_owner"

            continue
        fi

        LWBS_PLAN_GROUP_OWNERS["$group_name"]="$module_id"

        if account_group_exists "$group_name"; then
            if account_user_in_group \
                "$LWBS_TARGET_USER" \
                "$group_name"; then

                LWBS_PLAN_GROUP_ACTIONS["$plan_key"]="skip"
                ((LWBS_PLAN_SKIP_ACTION_COUNT += 1))

                log_info \
                    "Group membership plan: module=$module_id user=$LWBS_TARGET_USER group=$group_name action=skip"

                continue
            else
                membership_exit_code=$?

                if ((membership_exit_code != 1)); then
                    printf 'Error: unable to determine group membership for %s in %s.\n' \
                        "$LWBS_TARGET_USER" \
                        "$group_name" >&2

                    return "$membership_exit_code"
                fi
            fi

            LWBS_PLAN_GROUP_ACTIONS["$plan_key"]="add"
            ((LWBS_PLAN_ACCOUNT_ACTION_COUNT += 1))

        elif account_module_may_create_group "$module_id"; then
            LWBS_PLAN_GROUP_ACTIONS["$plan_key"]="deferred"
            ((LWBS_PLAN_ACCOUNT_ACTION_COUNT += 1))

        else
            printf 'Error: required group does not exist: %s\n' \
                "$group_name" >&2

            return 1
        fi

        restart_add_planned_requirement \
            logout \
            user-session \
            "Group membership '$group_name' for $LWBS_TARGET_USER requires a new login session"

        log_info \
            "Group membership plan: module=$module_id user=$LWBS_TARGET_USER group=$group_name action=${LWBS_PLAN_GROUP_ACTIONS[$plan_key]}"
    done

    return 0
}

account_module_has_planned_actions() {
    local module_id="${1:-}"
    local group_name
    local plan_key
    local action

    while IFS= read -r group_name; do
        [[ -z "$group_name" ]] && continue

        plan_key="$(
            account_group_plan_key \
                "$module_id" \
                "$group_name"
        )"

        action="${LWBS_PLAN_GROUP_ACTIONS[$plan_key]:-skip}"

        case "$action" in
            add | deferred)
                return 0
                ;;
        esac
    done <<<"${LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS[$module_id]:-}"

    return 1
}

account_plan_requires_privilege() {
    ((LWBS_PLAN_ACCOUNT_ACTION_COUNT > 0))
}

show_module_group_membership_plan() {
    local module_id="${1:-}"
    local group_name
    local plan_key
    local action
    local owner

    while IFS= read -r group_name; do
        [[ -z "$group_name" ]] && continue

        plan_key="$(
            account_group_plan_key \
                "$module_id" \
                "$group_name"
        )"

        action="${LWBS_PLAN_GROUP_ACTIONS[$plan_key]:-skip}"

        case "$action" in
            skip)
                printf '  Group         : %s -> %s [member, skip]\n' \
                    "$LWBS_TARGET_USER" \
                    "$group_name"
                ;;

            add)
                printf '  Group         : %s -> %s [add membership]\n' \
                    "$LWBS_TARGET_USER" \
                    "$group_name"
                ;;

            deferred)
                printf '  Group         : %s -> %s [add after module installation]\n' \
                    "$LWBS_TARGET_USER" \
                    "$group_name"
                ;;

            shared)
                owner="${LWBS_PLAN_GROUP_OWNERS[$group_name]}"

                printf '  Group         : %s -> %s [shared requirement, managed by %s]\n' \
                    "$LWBS_TARGET_USER" \
                    "$group_name" \
                    "$owner"
                ;;
        esac
    done <<<"${LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS[$module_id]:-}"
}

execute_planned_group_memberships() {
    local module_id="${1:-}"
    local group_name
    local plan_key
    local result_key
    local action
    local target
    local membership_exit_code
    local usermod_command
    local exit_code

    while IFS= read -r group_name; do
        [[ -z "$group_name" ]] && continue

        plan_key="$(
            account_group_plan_key \
                "$module_id" \
                "$group_name"
        )"

        result_key="$(
            account_result_key \
                "$module_id" \
                "$group_name"
        )"

        action="${LWBS_PLAN_GROUP_ACTIONS[$plan_key]:-skip}"
        target="$LWBS_TARGET_USER:$group_name"

        if ! account_user_exists "$LWBS_TARGET_USER"; then
            record_execution_result \
                "$result_key" \
                "group" \
                "$module_id" \
                "$target" \
                "failed" \
                "target user unavailable"

            return 1
        fi

        if ! account_group_exists "$group_name"; then
            record_execution_result \
                "$result_key" \
                "group" \
                "$module_id" \
                "$target" \
                "failed" \
                "required group unavailable"

            return 1
        fi

        if account_user_in_group \
            "$LWBS_TARGET_USER" \
            "$group_name"; then

            record_execution_result \
                "$result_key" \
                "group" \
                "$module_id" \
                "$target" \
                "skipped" \
                "group membership already satisfied"

            continue
        else
            membership_exit_code=$?

            if ((membership_exit_code != 1)); then
                record_execution_result \
                    "$result_key" \
                    "group" \
                    "$module_id" \
                    "$target" \
                    "unverifiable" \
                    "group membership state unavailable"

                return "$membership_exit_code"
            fi
        fi

        case "$action" in
            skip)
                record_execution_result \
                    "$result_key" \
                    "group" \
                    "$module_id" \
                    "$target" \
                    "failed" \
                    "planned group membership changed"

                return 1
                ;;

            shared)
                record_execution_result \
                    "$result_key" \
                    "group" \
                    "$module_id" \
                    "$target" \
                    "failed" \
                    "shared group requirement was not satisfied by its owner"

                return 1
                ;;

            add | deferred)
                ;;
        esac

        if usermod_command="$(account_usermod_command)"; then
            :
        else
            record_execution_result \
                "$result_key" \
                "group" \
                "$module_id" \
                "$target" \
                "failed" \
                "usermod command unavailable"

            return 1
        fi

        if run_privileged_command \
            "$usermod_command" \
            -a \
            -G "$group_name" \
            "$LWBS_TARGET_USER"; then
            :
        else
            exit_code=$?

            record_execution_result \
                "$result_key" \
                "group" \
                "$module_id" \
                "$target" \
                "failed" \
                "group membership update failed"

            return "$exit_code"
        fi

        if account_user_in_group \
            "$LWBS_TARGET_USER" \
            "$group_name"; then

            record_execution_result \
                "$result_key" \
                "group" \
                "$module_id" \
                "$target" \
                "successful" \
                "group membership verified"

            restart_add_recorded_requirement \
                logout \
                user-session \
                "Group membership '$group_name' for $LWBS_TARGET_USER requires a new login session"

            continue
        fi

        record_execution_result \
            "$result_key" \
            "group" \
            "$module_id" \
            "$target" \
            "failed" \
            "group membership was not active in account state after update"

        return 1
    done <<<"${LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS[$module_id]:-}"

    return 0
}

record_skipped_account_results() {
    local module_id="${1:-}"
    local group_name
    local result_key

    while IFS= read -r group_name; do
        [[ -z "$group_name" ]] && continue

        result_key="$(
            account_result_key \
                "$module_id" \
                "$group_name"
        )"

        record_execution_result \
            "$result_key" \
            "group" \
            "$module_id" \
            "$LWBS_TARGET_USER:$group_name" \
            "skipped" \
            "group membership already satisfied"
    done <<<"${LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS[$module_id]:-}"
}

reset_account_execution_plan() {
    LWBS_PLAN_ACCOUNT_ACTION_COUNT=0

    LWBS_PLAN_MODULE_GROUP_MEMBERSHIPS=()
    LWBS_PLAN_GROUP_ACTIONS=()
    LWBS_PLAN_GROUP_OWNERS=()
}