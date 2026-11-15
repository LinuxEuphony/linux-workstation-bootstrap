#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Module dependency and conflict resolution.
#
# This file:
# 1. Resolves required module dependencies transitively.
# 2. Places dependencies before dependent modules.
# 3. Prevents duplicate module execution.
# 4. Preserves deterministic root and dependency ordering.
# 5. Detects circular dependencies.
# 6. Detects missing dependencies.
# 7. Detects conflicts between resolved modules.
# 8. Rejects dependencies that were explicitly excluded.
#
# The resolver is read-only. It loads module metadata but performs no package,
# service, external-installer, or module apply actions.

declare -a LWBS_MODULE_GRAPH_RESULT=()
declare -a LWBS_MODULE_GRAPH_STACK=()

declare -A LWBS_MODULE_GRAPH_VISITING=()
declare -A LWBS_MODULE_GRAPH_VISITED=()
declare -A LWBS_MODULE_GRAPH_LOADED=()
declare -A LWBS_MODULE_GRAPH_DEPENDENCIES=()
declare -A LWBS_MODULE_GRAPH_CONFLICTS=()
declare -A LWBS_MODULE_GRAPH_EXCLUDED=()

reset_module_graph_state() {
    LWBS_MODULE_GRAPH_RESULT=()
    LWBS_MODULE_GRAPH_STACK=()

    LWBS_MODULE_GRAPH_VISITING=()
    LWBS_MODULE_GRAPH_VISITED=()
    LWBS_MODULE_GRAPH_LOADED=()
    LWBS_MODULE_GRAPH_DEPENDENCIES=()
    LWBS_MODULE_GRAPH_CONFLICTS=()
    LWBS_MODULE_GRAPH_EXCLUDED=()
}

module_graph_store_list() {
    local map_name="${1:-}"
    local key="${2:-}"
    shift 2

    local value
    local -n graph_map_ref="$map_name"

    graph_map_ref["$key"]=""

    for value in "$@"; do
        if [[ -n "${graph_map_ref[$key]}" ]]; then
            graph_map_ref["$key"]+=$'\n'"$value"
        else
            graph_map_ref["$key"]="$value"
        fi
    done
}

module_graph_load_metadata() {
    local module_id="${1:-}"
    local exit_code

    if [[ -n "${LWBS_MODULE_GRAPH_LOADED[$module_id]+defined}" ]]; then
        return 0
    fi

    if load_module "$module_id"; then
        :
    else
        exit_code=$?
        return "$exit_code"
    fi

    module_graph_store_list \
        LWBS_MODULE_GRAPH_DEPENDENCIES \
        "$module_id" \
        "${LWBS_MODULE_DEPENDENCIES[@]}"

    module_graph_store_list \
        LWBS_MODULE_GRAPH_CONFLICTS \
        "$module_id" \
        "${LWBS_MODULE_CONFLICTS[@]}"

    LWBS_MODULE_GRAPH_LOADED["$module_id"]=1

    reset_module_contract

    return 0
}

module_graph_cycle_description() {
    local repeated_module="${1:-}"
    local module_id
    local found_start=false
    local description=""

    for module_id in "${LWBS_MODULE_GRAPH_STACK[@]}"; do
        if [[ "$module_id" == "$repeated_module" ]]; then
            found_start=true
        fi

        if ! "$found_start"; then
            continue
        fi

        if [[ -n "$description" ]]; then
            description+=" -> "
        fi

        description+="$module_id"
    done

    if [[ -n "$description" ]]; then
        description+=" -> $repeated_module"
    else
        description="$repeated_module -> $repeated_module"
    fi

    printf '%s\n' "$description"
}

module_graph_visit() {
    local module_id="${1:-}"
    local required_by="${2:-}"
    local dependency
    local exit_code
    local stack_index
    local cycle_description

    if [[ -n "${LWBS_MODULE_GRAPH_EXCLUDED[$module_id]+defined}" ]]; then
        if [[ -n "$required_by" ]]; then
            printf 'Error: module %s requires excluded module: %s\n' \
                "$required_by" \
                "$module_id" >&2
        else
            printf 'Error: excluded module cannot be resolved: %s\n' \
                "$module_id" >&2
        fi

        return 1
    fi

    if [[ -n "${LWBS_MODULE_GRAPH_VISITED[$module_id]+defined}" ]]; then
        return 0
    fi

    if [[ -n "${LWBS_MODULE_GRAPH_VISITING[$module_id]+defined}" ]]; then
        cycle_description="$(module_graph_cycle_description "$module_id")"

        printf 'Error: circular module dependency detected: %s\n' \
            "$cycle_description" >&2

        return 1
    fi

    if module_graph_load_metadata "$module_id"; then
        :
    else
        exit_code=$?

        if [[ -n "$required_by" ]]; then
            printf 'Error: module %s requires unavailable dependency: %s\n' \
                "$required_by" \
                "$module_id" >&2
        else
            printf 'Error: unable to resolve module: %s\n' \
                "$module_id" >&2
        fi

        return "$exit_code"
    fi

    LWBS_MODULE_GRAPH_VISITING["$module_id"]=1
    LWBS_MODULE_GRAPH_STACK+=("$module_id")

    while IFS= read -r dependency; do
        [[ -z "$dependency" ]] && continue

        if module_graph_visit "$dependency" "$module_id"; then
            :
        else
            exit_code=$?

            unset 'LWBS_MODULE_GRAPH_VISITING[$module_id]'

            stack_index=$((${#LWBS_MODULE_GRAPH_STACK[@]} - 1))
            unset 'LWBS_MODULE_GRAPH_STACK[$stack_index]'

            return "$exit_code"
        fi
    done <<<"${LWBS_MODULE_GRAPH_DEPENDENCIES[$module_id]:-}"

    stack_index=$((${#LWBS_MODULE_GRAPH_STACK[@]} - 1))
    unset 'LWBS_MODULE_GRAPH_STACK[$stack_index]'

    unset 'LWBS_MODULE_GRAPH_VISITING[$module_id]'
    LWBS_MODULE_GRAPH_VISITED["$module_id"]=1

    LWBS_MODULE_GRAPH_RESULT+=("$module_id")

    return 0
}

module_graph_validate_conflicts() {
    local module_id
    local conflicting_module

    local -A resolved_set=()

    for module_id in "${LWBS_MODULE_GRAPH_RESULT[@]}"; do
        resolved_set["$module_id"]=1
    done

    for module_id in "${LWBS_MODULE_GRAPH_RESULT[@]}"; do
        while IFS= read -r conflicting_module; do
            [[ -z "$conflicting_module" ]] && continue

            if [[ -n "${resolved_set[$conflicting_module]+defined}" ]]; then
                printf 'Error: conflicting modules selected: %s conflicts with %s\n' \
                    "$module_id" \
                    "$conflicting_module" >&2

                return 1
            fi
        done <<<"${LWBS_MODULE_GRAPH_CONFLICTS[$module_id]:-}"
    done

    return 0
}

resolve_module_graph() {
    local result_name="${1:-}"
    local selected_name="${2:-}"
    local excluded_name="${3:-}"
    local module_id
    local exit_code

    if [[ ! "$result_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ||
        ! "$selected_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ||
        ! "$excluded_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then

        printf 'Error: invalid array name provided to module graph resolver.\n' \
            >&2
        return 2
    fi

    local -n result_ref="$result_name"
    local -n selected_ref="$selected_name"
    local -n excluded_ref="$excluded_name"

    result_ref=()

    if ((${#selected_ref[@]} == 0)); then
        printf 'Error: module graph cannot resolve an empty module selection.\n' \
            >&2
        return 1
    fi

    reset_module_graph_state

    for module_id in "${excluded_ref[@]}"; do
        LWBS_MODULE_GRAPH_EXCLUDED["$module_id"]=1
    done

    for module_id in "${selected_ref[@]}"; do
        if module_graph_visit "$module_id" ""; then
            :
        else
            exit_code=$?
            reset_module_graph_state
            return "$exit_code"
        fi
    done

    if module_graph_validate_conflicts; then
        :
    else
        exit_code=$?
        reset_module_graph_state
        return "$exit_code"
    fi

    result_ref=("${LWBS_MODULE_GRAPH_RESULT[@]}")

    log_info \
        "Module graph resolved: selected=${#selected_ref[@]} resolved=${#result_ref[@]}"

    reset_module_graph_state

    return 0
}
