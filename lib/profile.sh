#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Workstation profile utilities.
# Provides the controlled interface used to load and validate declarative
# workstation profiles.
#
# Profile execution is delegated to the execution-plan framework so all
# package, external software, and custom module actions are resolved before
# any system-changing operation begins.

LWBS_PROFILE_ID=""
LWBS_PROFILE_NAME=""
LWBS_PROFILE_DESCRIPTION=""
LWBS_PROFILE_PATH=""

declare -a LWBS_PROFILE_MODULES=()

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