#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Installation module utilities.
# Provides the controlled interface used to load, validate, and execute
# reusable workstation capability modules.
#
# This file:
# 1. Loads workstation modules from the modules directory.
# 2. Validates the module contract.
# 3. Captures module metadata and capability requirements.
# 4. Resolves capabilities through the selected distro package mapping.
# 5. Checks resolved package installation state through the distro adapter.
# 6. Skips package requirements that are already satisfied.
# 7. Routes missing packages through the selected distro adapter.
# 8. Supports optional module-specific operations.
# 9. Preserves dry-run behaviour through shared execution utilities.

LWBS_MODULE_ID=""
LWBS_MODULE_NAME=""
LWBS_MODULE_DESCRIPTION=""
LWBS_MODULE_PATH=""

declare -a LWBS_MODULE_CAPABILITIES=()

load_module() {
    local requested_module="${1:-}"
    local module_directory
    local module_path
    local capability_output
    local capability

    if [[ -z "$requested_module" ]]; then
        printf 'Error: no module was provided.\n' >&2
        log_error "Module load requested without a module ID."
        return 2
    fi

    if [[ ! "$requested_module" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid module ID: %s\n' \
            "$requested_module" >&2

        log_error \
            "Invalid module ID requested: $requested_module"

        return 2
    fi

    module_directory="${LWBS_MODULES_DIR_OVERRIDE:-$LWBS_ROOT/modules}"
    module_path="$module_directory/$requested_module.sh"

    if [[ ! -r "$module_path" ]]; then
        printf 'Error: module not found: %s\n' \
            "$module_path" >&2

        log_error \
            "Module file not found: module=$requested_module path=$module_path"

        return 1
    fi

    reset_module_contract

    log_info "Loading module: $requested_module"

    # shellcheck disable=SC1090
    if ! source "$module_path"; then
        printf 'Error: failed to load module: %s\n' \
            "$requested_module" >&2

        log_error \
            "Module source failed: module=$requested_module path=$module_path"

        reset_module_contract
        return 1
    fi

    if ! validate_module_contract; then
        log_error \
            "Module contract validation failed: $requested_module"

        reset_module_contract
        return 1
    fi

    LWBS_MODULE_ID="$(module_id)"
    LWBS_MODULE_NAME="$(module_name)"
    LWBS_MODULE_DESCRIPTION="$(module_description)"

    if [[ -z "$LWBS_MODULE_ID" ]]; then
        printf 'Error: module returned an empty module ID.\n' >&2
        log_error "Module returned an empty ID: $requested_module"
        reset_module_contract
        return 1
    fi

    if [[ "$LWBS_MODULE_ID" != "$requested_module" ]]; then
        printf 'Error: module ID mismatch: requested %s, module declared %s\n' \
            "$requested_module" \
            "$LWBS_MODULE_ID" >&2

        log_error \
            "Module ID mismatch: requested=$requested_module declared=$LWBS_MODULE_ID"

        reset_module_contract
        return 1
    fi

    if [[ -z "$LWBS_MODULE_NAME" ]]; then
        printf 'Error: module returned an empty display name: %s\n' \
            "$requested_module" >&2

        log_error \
            "Module returned an empty display name: $requested_module"

        reset_module_contract
        return 1
    fi

    if [[ -z "$LWBS_MODULE_DESCRIPTION" ]]; then
        printf 'Error: module returned an empty description: %s\n' \
            "$requested_module" >&2

        log_error \
            "Module returned an empty description: $requested_module"

        reset_module_contract
        return 1
    fi

    if capability_output="$(module_capabilities)"; then
        :
    else
        printf 'Error: unable to read capability requirements for module: %s\n' \
            "$requested_module" >&2

        log_error \
            "Module capability requirement resolution failed: $requested_module"

        reset_module_contract
        return 1
    fi

    LWBS_MODULE_CAPABILITIES=()

    while IFS= read -r capability; do
        if [[ -z "$capability" ]]; then
            continue
        fi

        if [[ ! "$capability" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
            printf 'Error: invalid capability declaration in module %s: %s\n' \
                "$requested_module" \
                "$capability" >&2

            log_error \
                "Invalid capability declaration: module=$requested_module capability=$capability"

            reset_module_contract
            return 1
        fi

        LWBS_MODULE_CAPABILITIES+=("$capability")
    done <<<"$capability_output"

    if ((${#LWBS_MODULE_CAPABILITIES[@]} == 0)) &&
        ! declare -F module_apply >/dev/null 2>&1; then
        printf 'Error: module %s does not declare any actions.\n' \
            "$requested_module" >&2

        log_error \
            "Module contains no capability requirements or operation hook: $requested_module"

        reset_module_contract
        return 1
    fi

    LWBS_MODULE_PATH="$module_path"

    log_info \
        "Module loaded: id=$LWBS_MODULE_ID capability_count=${#LWBS_MODULE_CAPABILITIES[@]}"

    return 0
}

validate_module_contract() {
    local required_function

    local -a required_functions=(
        "module_id"
        "module_name"
        "module_description"
        "module_capabilities"
    )

    for required_function in "${required_functions[@]}"; do
        if ! declare -F "$required_function" >/dev/null 2>&1; then
            printf 'Error: module is missing required function: %s\n' \
                "$required_function" >&2

            return 1
        fi
    done

    return 0
}

# Separate resolved packages into requirements that are already satisfied and
# packages that still require installation.
collect_missing_module_packages() {
    local result_name="${1:-}"
    local package
    local package_state
    local exit_code

    if [[ -z "$result_name" ]]; then
        printf 'Error: no output array was provided for package-state evaluation.\n' \
            >&2
        return 2
    fi

    if [[ ! "$result_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'Error: invalid output array name for package-state evaluation: %s\n' \
            "$result_name" >&2
        return 2
    fi

    shift

    # Use a distinct local nameref name so a caller array named
    # "missing_packages" cannot create a circular name reference.
    local -n output_array_ref="$result_name"

    output_array_ref=()

    for package in "$@"; do
        if package_state="$(distro_package_state "$package")"; then
            :
        else
            exit_code=$?

            printf 'Error: unable to determine package state: %s\n' \
                "$package" >&2

            log_error \
                "Package state check failed: module=$LWBS_MODULE_ID package=$package exit_code=$exit_code"

            return "$exit_code"
        fi

        case "$package_state" in
            installed)
                printf '    - %s [installed, skip]\n' "$package"

                log_info \
                    "Package requirement already satisfied: module=$LWBS_MODULE_ID package=$package"
                ;;

            absent)
                printf '    - %s [missing]\n' "$package"

                log_info \
                    "Package requirement not satisfied: module=$LWBS_MODULE_ID package=$package"

                output_array_ref+=("$package")
                ;;

            *)
                printf 'Error: distribution adapter returned invalid package state "%s" for %s.\n' \
                    "$package_state" \
                    "$package" >&2

                log_error \
                    "Invalid package state returned by distro adapter: module=$LWBS_MODULE_ID package=$package state=$package_state"

                return 1
                ;;
        esac
    done

    return 0
}

execute_loaded_module() {
    local capability
    local exit_code
    local package

    local -a resolved_packages=()
    local -a missing_packages=()

    if [[ -z "$LWBS_MODULE_ID" ]]; then
        printf 'Error: no module is currently loaded.\n' >&2
        log_error "Module execution requested without a loaded module."
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ]]; then
        printf 'Error: a distribution adapter must be loaded before executing modules.\n' \
            >&2

        log_error \
            "Module execution requested without a distribution adapter: module=$LWBS_MODULE_ID"

        return 1
    fi

    if [[ -z "${LWBS_CAPABILITY_PROFILE:-}" ]]; then
        printf 'Error: a capability mapping must be loaded before executing modules.\n' \
            >&2

        log_error \
            "Module execution requested without a capability mapping: module=$LWBS_MODULE_ID"

        return 1
    fi

    if [[ "$LWBS_CAPABILITY_PROFILE" != "$DISTRO_ADAPTER_PROFILE" ]]; then
        printf 'Error: capability mapping profile "%s" does not match distribution adapter "%s".\n' \
            "$LWBS_CAPABILITY_PROFILE" \
            "$DISTRO_ADAPTER_PROFILE" >&2

        log_error \
            "Capability and distro profile mismatch: capability_profile=$LWBS_CAPABILITY_PROFILE adapter_profile=$DISTRO_ADAPTER_PROFILE module=$LWBS_MODULE_ID"

        return 1
    fi

    if ! declare -F distro_install_packages >/dev/null 2>&1; then
        printf 'Error: the loaded distribution adapter cannot install packages.\n' \
            >&2
        return 1
    fi

    if ! declare -F distro_package_state >/dev/null 2>&1; then
        printf 'Error: the loaded distribution adapter cannot determine package state.\n' \
            >&2
        return 1
    fi

    printf '\nModule: %s\n' "$LWBS_MODULE_NAME"
    printf '  ID          : %s\n' "$LWBS_MODULE_ID"
    printf '  Description : %s\n' "$LWBS_MODULE_DESCRIPTION"

    log_info \
        "Executing module: id=$LWBS_MODULE_ID name=$LWBS_MODULE_NAME"

    if ((${#LWBS_MODULE_CAPABILITIES[@]} > 0)); then
        printf '  Capabilities: %d\n' "${#LWBS_MODULE_CAPABILITIES[@]}"

        for capability in "${LWBS_MODULE_CAPABILITIES[@]}"; do
            printf '    - %s\n' "$capability"
        done

        if resolve_capabilities \
            resolved_packages \
            "${LWBS_MODULE_CAPABILITIES[@]}"; then
            :
        else
            exit_code=$?

            log_error \
                "Module capability resolution failed: module=$LWBS_MODULE_ID exit_code=$exit_code"

            return "$exit_code"
        fi

        if ((${#resolved_packages[@]} == 0)); then
            printf 'Error: module capabilities resolved to no packages: %s\n' \
                "$LWBS_MODULE_ID" >&2

            return 1
        fi

        printf '  Package state:\n'

        if collect_missing_module_packages \
            missing_packages \
            "${resolved_packages[@]}"; then
            :
        else
            exit_code=$?
            return "$exit_code"
        fi

        if ((${#missing_packages[@]} == 0)); then
            printf '  Action      : package requirements already satisfied\n'

            log_info \
                "Module package installation skipped because all requirements are satisfied: $LWBS_MODULE_ID"
        else
            printf '  Install     : %d package(s)\n' \
                "${#missing_packages[@]}"

            for package in "${missing_packages[@]}"; do
                printf '    - %s\n' "$package"
            done

            log_info \
                "Installing missing module packages: module=$LWBS_MODULE_ID count=${#missing_packages[@]}"

            if distro_install_packages "${missing_packages[@]}"; then
                :
            else
                exit_code=$?

                log_error \
                    "Module package installation failed: module=$LWBS_MODULE_ID exit_code=$exit_code"

                return "$exit_code"
            fi

            if "$LWBS_DRY_RUN"; then
                log_info \
                    "Dry-run package installation completed: module=$LWBS_MODULE_ID count=${#missing_packages[@]}"
            else
                log_info \
                    "Module package installation completed: module=$LWBS_MODULE_ID count=${#missing_packages[@]}"
            fi
        fi
    fi

    if declare -F module_apply >/dev/null 2>&1; then
        log_info \
            "Executing module operation hook: $LWBS_MODULE_ID"

        if module_apply; then
            :
        else
            exit_code=$?

            log_error \
                "Module operation failed: module=$LWBS_MODULE_ID exit_code=$exit_code"

            return "$exit_code"
        fi
    fi

    log_info \
        "Module completed successfully: $LWBS_MODULE_ID"

    return 0
}

run_module() {
    local module_id="${1:-}"
    local exit_code

    if load_module "$module_id"; then
        :
    else
        exit_code=$?
        return "$exit_code"
    fi

    execute_loaded_module
}

reset_module_contract() {
    unset -f \
        module_id \
        module_name \
        module_description \
        module_capabilities \
        module_apply \
        2>/dev/null || true

    LWBS_MODULE_ID=""
    LWBS_MODULE_NAME=""
    LWBS_MODULE_DESCRIPTION=""
    LWBS_MODULE_PATH=""
    LWBS_MODULE_CAPABILITIES=()
}