#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Workstation profile utilities.
# Provides the controlled interface used to load, validate, resolve, and list
# declarative workstation profiles.
#
# Profile execution is delegated to the execution-plan framework so all
# package, external software, service, and custom module actions are resolved
# before any system-changing operation begins.

LWBS_PROFILE_ID=""
LWBS_PROFILE_NAME=""
LWBS_PROFILE_DESCRIPTION=""
LWBS_PROFILE_PATH=""

declare -a LWBS_PROFILE_MODULES=()

read_profile_metadata() (
    local profile_path="${1:-}"
    local required_function
    local metadata_id
    local metadata_name
    local metadata_description

    if [[ ! -r "$profile_path" ]]; then
        return 1
    fi

    unset -f \
        profile_id \
        profile_name \
        profile_description \
        profile_modules \
        2>/dev/null || true

    # shellcheck disable=SC1090
    if ! source "$profile_path"; then
        return 1
    fi

    for required_function in \
        profile_id \
        profile_name \
        profile_description; do

        if ! declare -F "$required_function" >/dev/null 2>&1; then
            return 1
        fi
    done

    metadata_id="$(profile_id)"
    metadata_name="$(profile_name)"
    metadata_description="$(profile_description)"

    if [[ ! "$metadata_id" =~ ^[a-z0-9][a-z0-9_-]*$ ||
        -z "$metadata_name" ||
        -z "$metadata_description" ]]; then

        return 1
    fi

    printf '%s\t%s\t%s\n' \
        "$metadata_id" \
        "$metadata_name" \
        "$metadata_description"
)

list_available_profiles() {
    local profile_directory
    local profile_path
    local metadata
    local profile_id_value
    local profile_name_value
    local profile_description_value
    local found_profile=false

    profile_directory="${LWBS_PROFILES_DIR_OVERRIDE:-$LWBS_ROOT/profiles}"

    printf 'Available workstation profiles:\n\n'

    for profile_path in "$profile_directory"/*.sh; do
        [[ -f "$profile_path" ]] || continue

        if metadata="$(read_profile_metadata "$profile_path")"; then
            :
        else
            continue
        fi

        IFS=$'\t' read -r \
            profile_id_value \
            profile_name_value \
            profile_description_value <<<"$metadata"

        printf '  %-18s %s\n' \
            "$profile_id_value" \
            "$profile_name_value"

        printf '  %-18s %s\n\n' \
            "" \
            "$profile_description_value"

        found_profile=true
    done

    if ! "$found_profile"; then
        printf '  No workstation profiles are available.\n'
        return 1
    fi

    return 0
}

validate_profile_selection_module() {
    local module_id="${1:-}"
    local exit_code

    if load_module "$module_id"; then
        reset_module_contract
        return 0
    else
        exit_code=$?
        reset_module_contract
        return "$exit_code"
    fi
}

apply_profile_module_selection() {
    local module_id
    local requested_module
    local excluded_module

    local -a requested_modules=()
    local -a excluded_modules=()
    local -a selected_modules=()
    local -a final_modules=()

    local -A seen_modules=()
    local -A excluded_module_set=()

    if declare -p LWBS_REQUESTED_MODULES >/dev/null 2>&1; then
        requested_modules=("${LWBS_REQUESTED_MODULES[@]}")
    fi

    if declare -p LWBS_EXCLUDED_MODULES >/dev/null 2>&1; then
        excluded_modules=("${LWBS_EXCLUDED_MODULES[@]}")
    fi

    for requested_module in "${requested_modules[@]}"; do
        for excluded_module in "${excluded_modules[@]}"; do
            if [[ "$requested_module" == "$excluded_module" ]]; then
                printf 'Error: module cannot be both included and excluded: %s\n' \
                    "$requested_module" >&2
                return 2
            fi
        done
    done

    for module_id in "${LWBS_PROFILE_MODULES[@]}"; do
        if [[ -n "${seen_modules[$module_id]+defined}" ]]; then
            printf 'Error: profile %s contains duplicate module: %s\n' \
                "$LWBS_PROFILE_ID" \
                "$module_id" >&2
            return 1
        fi

        seen_modules["$module_id"]=1
        selected_modules+=("$module_id")
    done

    for requested_module in "${requested_modules[@]}"; do
        if [[ -n "${seen_modules[$requested_module]+defined}" ]]; then
            continue
        fi

        if validate_profile_selection_module "$requested_module"; then
            :
        else
            printf 'Error: requested module is unavailable: %s\n' \
                "$requested_module" >&2
            return 1
        fi

        seen_modules["$requested_module"]=1
        selected_modules+=("$requested_module")
    done

    for excluded_module in "${excluded_modules[@]}"; do
        if validate_profile_selection_module "$excluded_module"; then
            :
        else
            printf 'Error: excluded module is unavailable: %s\n' \
                "$excluded_module" >&2
            return 1
        fi

        if [[ -z "${seen_modules[$excluded_module]+defined}" ]]; then
            printf 'Error: cannot exclude a module that is not selected: %s\n' \
                "$excluded_module" >&2
            return 1
        fi

        excluded_module_set["$excluded_module"]=1
    done

    for module_id in "${selected_modules[@]}"; do
        if [[ -n "${excluded_module_set[$module_id]+defined}" ]]; then
            continue
        fi

        final_modules+=("$module_id")
    done

    if ((${#final_modules[@]} == 0)); then
        printf 'Error: workstation profile selection contains no modules.\n' \
            >&2
        return 1
    fi

    LWBS_PROFILE_MODULES=("${final_modules[@]}")

    log_info \
        "Resolved workstation profile modules: profile=$LWBS_PROFILE_ID module_count=${#LWBS_PROFILE_MODULES[@]}"

    return 0
}

load_profile() {
    local requested_profile="${1:-}"
    local profile_directory
    local profile_path
    local module_output
    local module_id

    if [[ -z "$requested_profile" ]]; then
        printf 'Error: no profile was provided.\n' >&2
        log_error "Profile load requested without a profile ID."
        return 2
    fi

    if [[ ! "$requested_profile" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid profile ID: %s\n' \
            "$requested_profile" >&2

        return 2
    fi

    profile_directory="${LWBS_PROFILES_DIR_OVERRIDE:-$LWBS_ROOT/profiles}"
    profile_path="$profile_directory/$requested_profile.sh"

    if [[ ! -r "$profile_path" ]]; then
        printf 'Error: profile not found: %s\n' \
            "$profile_path" >&2

        return 1
    fi

    reset_profile_contract

    log_info "Loading profile: $requested_profile"

    # shellcheck disable=SC1090
    if ! source "$profile_path"; then
        printf 'Error: failed to load profile: %s\n' \
            "$requested_profile" >&2

        reset_profile_contract
        return 1
    fi

    if ! validate_profile_contract; then
        reset_profile_contract
        return 1
    fi

    LWBS_PROFILE_ID="$(profile_id)"
    LWBS_PROFILE_NAME="$(profile_name)"
    LWBS_PROFILE_DESCRIPTION="$(profile_description)"

    if [[ -z "$LWBS_PROFILE_ID" ]]; then
        printf 'Error: profile returned an empty profile ID.\n' >&2
        reset_profile_contract
        return 1
    fi

    if [[ "$LWBS_PROFILE_ID" != "$requested_profile" ]]; then
        printf 'Error: profile ID mismatch: requested %s, profile declared %s\n' \
            "$requested_profile" \
            "$LWBS_PROFILE_ID" >&2

        reset_profile_contract
        return 1
    fi

    if [[ -z "$LWBS_PROFILE_NAME" ]]; then
        printf 'Error: profile returned an empty display name: %s\n' \
            "$requested_profile" >&2

        reset_profile_contract
        return 1
    fi

    if [[ -z "$LWBS_PROFILE_DESCRIPTION" ]]; then
        printf 'Error: profile returned an empty description: %s\n' \
            "$requested_profile" >&2

        reset_profile_contract
        return 1
    fi

    if module_output="$(profile_modules)"; then
        :
    else
        printf 'Error: unable to read module selections for profile: %s\n' \
            "$requested_profile" >&2

        reset_profile_contract
        return 1
    fi

    LWBS_PROFILE_MODULES=()

    while IFS= read -r module_id; do
        [[ -z "$module_id" ]] && continue

        if [[ ! "$module_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            printf 'Error: invalid module ID in profile %s: %s\n' \
                "$requested_profile" \
                "$module_id" >&2

            reset_profile_contract
            return 1
        fi

        LWBS_PROFILE_MODULES+=("$module_id")
    done <<<"$module_output"

    if ((${#LWBS_PROFILE_MODULES[@]} == 0)); then
        printf 'Error: profile %s does not select any modules.\n' \
            "$requested_profile" >&2

        reset_profile_contract
        return 1
    fi

    LWBS_PROFILE_PATH="$profile_path"

    if ! validate_profile_modules; then
        reset_profile_contract
        return 1
    fi

    if ! apply_profile_module_selection; then
        reset_profile_contract
        return 1
    fi

    log_info \
        "Profile loaded: id=$LWBS_PROFILE_ID module_count=${#LWBS_PROFILE_MODULES[@]}"

    return 0
}

validate_profile_contract() {
    local required_function

    local -a required_functions=(
        "profile_id"
        "profile_name"
        "profile_description"
        "profile_modules"
    )

    for required_function in "${required_functions[@]}"; do
        if ! declare -F "$required_function" >/dev/null 2>&1; then
            printf 'Error: profile is missing required function: %s\n' \
                "$required_function" >&2

            return 1
        fi
    done

    return 0
}

validate_profile_modules() {
    local module_id
    local exit_code

    for module_id in "${LWBS_PROFILE_MODULES[@]}"; do
        if load_module "$module_id"; then
            :
        else
            exit_code=$?

            printf 'Error: profile %s references an invalid or unavailable module: %s\n' \
                "$LWBS_PROFILE_ID" \
                "$module_id" >&2

            reset_module_contract
            return "$exit_code"
        fi

        reset_module_contract
    done

    return 0
}

# Execute the currently loaded profile through the mandatory planning layer.
execute_loaded_profile() {
    if [[ -z "$LWBS_PROFILE_ID" ]]; then
        printf 'Error: no profile is currently loaded.\n' >&2
        return 2
    fi

    if ! declare -F run_profile_execution_plan >/dev/null 2>&1; then
        printf 'Error: execution-plan framework is unavailable.\n' >&2
        return 1
    fi

    run_profile_execution_plan "$LWBS_PROFILE_ID"
}

# Load and execute a profile through the mandatory execution-plan workflow.
run_profile() {
    local profile_id="${1:-}"

    if ! declare -F run_profile_execution_plan >/dev/null 2>&1; then
        printf 'Error: execution-plan framework is unavailable.\n' >&2
        return 1
    fi

    run_profile_execution_plan "$profile_id"
}

reset_profile_contract() {
    unset -f \
        profile_id \
        profile_name \
        profile_description \
        profile_modules \
        2>/dev/null || true

    LWBS_PROFILE_ID=""
    LWBS_PROFILE_NAME=""
    LWBS_PROFILE_DESCRIPTION=""
    LWBS_PROFILE_PATH=""
    LWBS_PROFILE_MODULES=()
}
