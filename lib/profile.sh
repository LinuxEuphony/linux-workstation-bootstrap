#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Workstation profile utilities.
# Provides the controlled interface used to load, validate, and execute
# declarative workstation profiles.
#
# This file:
# 1. Loads workstation profiles from the profiles directory.
# 2. Validates the profile contract.
# 3. Captures profile metadata and selected modules.
# 4. Validates referenced modules before profile execution.
# 5. Executes profile modules through the shared module framework.
# 6. Preserves dry-run behaviour through module and distro execution layers.

# State for the profile currently loaded by the bootstrap.
LWBS_PROFILE_ID=""
LWBS_PROFILE_NAME=""
LWBS_PROFILE_DESCRIPTION=""
LWBS_PROFILE_PATH=""

declare -a LWBS_PROFILE_MODULES=()

# Load a workstation profile by ID.
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

    # Restrict profile IDs to predictable file-safe identifiers.
    if [[ ! "$requested_profile" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid profile ID: %s\n' \
            "$requested_profile" >&2

        log_error \
            "Invalid profile ID requested: $requested_profile"

        return 2
    fi

    profile_directory="${LWBS_PROFILES_DIR_OVERRIDE:-$LWBS_ROOT/profiles}"
    profile_path="$profile_directory/$requested_profile.sh"

    if [[ ! -r "$profile_path" ]]; then
        printf 'Error: profile not found: %s\n' \
            "$profile_path" >&2

        log_error \
            "Profile file not found: profile=$requested_profile path=$profile_path"

        return 1
    fi

    # Remove the previous profile contract before loading another profile so
    # stale functions cannot make an incomplete profile appear valid.
    reset_profile_contract

    log_info "Loading profile: $requested_profile"

    # shellcheck disable=SC1090
    if ! source "$profile_path"; then
        printf 'Error: failed to load profile: %s\n' \
            "$requested_profile" >&2

        log_error \
            "Profile source failed: profile=$requested_profile path=$profile_path"

        reset_profile_contract
        return 1
    fi

    if ! validate_profile_contract; then
        log_error \
            "Profile contract validation failed: $requested_profile"

        reset_profile_contract
        return 1
    fi

    # Read profile metadata only after the contract has been validated.
    LWBS_PROFILE_ID="$(profile_id)"
    LWBS_PROFILE_NAME="$(profile_name)"
    LWBS_PROFILE_DESCRIPTION="$(profile_description)"

    if [[ -z "$LWBS_PROFILE_ID" ]]; then
        printf 'Error: profile returned an empty profile ID.\n' >&2
        log_error "Profile returned an empty ID: $requested_profile"
        reset_profile_contract
        return 1
    fi

    if [[ "$LWBS_PROFILE_ID" != "$requested_profile" ]]; then
        printf 'Error: profile ID mismatch: requested %s, profile declared %s\n' \
            "$requested_profile" \
            "$LWBS_PROFILE_ID" >&2

        log_error \
            "Profile ID mismatch: requested=$requested_profile declared=$LWBS_PROFILE_ID"

        reset_profile_contract
        return 1
    fi

    if [[ -z "$LWBS_PROFILE_NAME" ]]; then
        printf 'Error: profile returned an empty display name: %s\n' \
            "$requested_profile" >&2

        log_error \
            "Profile returned an empty display name: $requested_profile"

        reset_profile_contract
        return 1
    fi

    if [[ -z "$LWBS_PROFILE_DESCRIPTION" ]]; then
        printf 'Error: profile returned an empty description: %s\n' \
            "$requested_profile" >&2

        log_error \
            "Profile returned an empty description: $requested_profile"

        reset_profile_contract
        return 1
    fi

    # Collect module selections as one module ID per line.
    if ! module_output="$(profile_modules)"; then
        printf 'Error: unable to read module selections for profile: %s\n' \
            "$requested_profile" >&2

        log_error \
            "Profile module resolution failed: $requested_profile"

        reset_profile_contract
        return 1
    fi

    LWBS_PROFILE_MODULES=()

    while IFS= read -r module_id; do
        if [[ -z "$module_id" ]]; then
            continue
        fi

        if [[ ! "$module_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            printf 'Error: invalid module ID in profile %s: %s\n' \
                "$requested_profile" \
                "$module_id" >&2

            log_error \
                "Invalid profile module declaration: profile=$requested_profile module=$module_id"

            reset_profile_contract
            return 1
        fi

        LWBS_PROFILE_MODULES+=("$module_id")
    done <<<"$module_output"

    if ((${#LWBS_PROFILE_MODULES[@]} == 0)); then
        printf 'Error: profile %s does not select any modules.\n' \
            "$requested_profile" >&2

        log_error \
            "Profile contains no module selections: $requested_profile"

        reset_profile_contract
        return 1
    fi

    LWBS_PROFILE_PATH="$profile_path"

    # Validate every referenced module before the profile is accepted.
    if ! validate_profile_modules; then
        log_error \
            "Profile module validation failed: $requested_profile"

        reset_profile_contract
        return 1
    fi

    log_info \
        "Profile loaded: id=$LWBS_PROFILE_ID module_count=${#LWBS_PROFILE_MODULES[@]}"

    return 0
}

# Validate the interface required from every workstation profile.
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

# Validate every module referenced by the currently loaded profile.
validate_profile_modules() {
    local module_id

    for module_id in "${LWBS_PROFILE_MODULES[@]}"; do
        if ! load_module "$module_id"; then
            printf 'Error: profile %s references an invalid or unavailable module: %s\n' \
                "$LWBS_PROFILE_ID" \
                "$module_id" >&2

            log_error \
                "Profile references invalid module: profile=$LWBS_PROFILE_ID module=$module_id"

            reset_module_contract
            return 1
        fi

        # Module validation should not leave one of the profile modules loaded.
        reset_module_contract
    done

    return 0
}

# Execute the profile currently loaded by load_profile().
execute_loaded_profile() {
    local module_id
    local exit_code

    if [[ -z "$LWBS_PROFILE_ID" ]]; then
        printf 'Error: no profile is currently loaded.\n' >&2
        log_error "Profile execution requested without a loaded profile."
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ]]; then
        printf 'Error: a distribution adapter must be loaded before executing profiles.\n' \
            >&2

        log_error \
            "Profile execution requested without a distribution adapter: profile=$LWBS_PROFILE_ID"

        return 1
    fi

    printf '\nProfile: %s\n' "$LWBS_PROFILE_NAME"
    printf '  ID          : %s\n' "$LWBS_PROFILE_ID"
    printf '  Description : %s\n' "$LWBS_PROFILE_DESCRIPTION"
    printf '  Modules     : %d\n' "${#LWBS_PROFILE_MODULES[@]}"

    for module_id in "${LWBS_PROFILE_MODULES[@]}"; do
        printf '    - %s\n' "$module_id"
    done

    log_info \
        "Executing profile: id=$LWBS_PROFILE_ID name=$LWBS_PROFILE_NAME module_count=${#LWBS_PROFILE_MODULES[@]}"

    # Execute modules in the order declared by the profile.
    for module_id in "${LWBS_PROFILE_MODULES[@]}"; do
        if run_module "$module_id"; then
            continue
        else
            exit_code=$?

            log_error \
                "Profile module execution failed: profile=$LWBS_PROFILE_ID module=$module_id exit_code=$exit_code"

            return "$exit_code"
        fi
    done

    log_info \
        "Profile completed successfully: $LWBS_PROFILE_ID"

    return 0
}

# Load and execute a workstation profile through the controlled profile path.
run_profile() {
    local profile_id="${1:-}"
    local exit_code

    if load_profile "$profile_id"; then
        :
    else
        exit_code=$?
        return "$exit_code"
    fi

    execute_loaded_profile
}

# Remove functions and state belonging to the current profile contract.
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