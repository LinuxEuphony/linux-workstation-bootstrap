#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Installation module utilities.
# Provides the controlled interface used to load and validate reusable
# workstation capability modules.

LWBS_MODULE_ID=""
LWBS_MODULE_NAME=""
LWBS_MODULE_DESCRIPTION=""
LWBS_MODULE_PATH=""

declare -a LWBS_MODULE_CAPABILITIES=()
declare -a LWBS_MODULE_DEPENDENCIES=()
declare -a LWBS_MODULE_CONFLICTS=()
declare -a LWBS_MODULE_EXTERNAL_INSTALLERS=()
declare -a LWBS_MODULE_SERVICES=()
declare -a LWBS_MODULE_CONFIGURATIONS=()
declare -a LWBS_MODULE_GROUP_MEMBERSHIPS=()
declare -a LWBS_MODULE_RESTART_REQUIREMENTS=()

load_module() {
    local requested_module="${1:-}"
    local module_directory
    local module_path
    local capability_output
    local dependency_output
    local conflict_output
    local external_output
    local service_output
    local configuration_output
    local group_output
    local restart_output

    local capability
    local dependency
    local conflict
    local installer_id
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy

    local configuration_requirement
    local configuration_id
    local configuration_kind
    local configuration_scope
    local configuration_destination
    local configuration_source
    local configuration_mode
    local configuration_backup

    local group_name

    local restart_requirement
    local restart_type
    local restart_target
    local restart_reason

    local -A seen_dependencies=()
    local -A seen_conflicts=()
    local -A seen_external_installers=()
    local -A seen_services=()
    local -A seen_configurations=()
    local -A seen_groups=()
    local -A seen_restart_requirements=()

    if [[ -z "$requested_module" ]]; then
        printf 'Error: no module was provided.\n' >&2
        log_error "Module load requested without a module ID."
        return 2
    fi

    if [[ ! "$requested_module" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid module ID: %s\n' \
            "$requested_module" >&2

        return 2
    fi

    module_directory="${LWBS_MODULES_DIR_OVERRIDE:-$LWBS_ROOT/modules}"
    module_path="$module_directory/$requested_module.sh"

    if [[ ! -r "$module_path" ]]; then
        printf 'Error: module not found: %s\n' \
            "$module_path" >&2

        return 1
    fi

    reset_module_contract

    log_info "Loading module: $requested_module"

    # shellcheck disable=SC1090
    if ! source "$module_path"; then
        printf 'Error: failed to load module: %s\n' \
            "$requested_module" >&2

        reset_module_contract
        return 1
    fi

    if ! validate_module_contract; then
        reset_module_contract
        return 1
    fi

    LWBS_MODULE_ID="$(module_id)"
    LWBS_MODULE_NAME="$(module_name)"
    LWBS_MODULE_DESCRIPTION="$(module_description)"

    if [[ -z "$LWBS_MODULE_ID" ||
        "$LWBS_MODULE_ID" != "$requested_module" ||
        -z "$LWBS_MODULE_NAME" ||
        -z "$LWBS_MODULE_DESCRIPTION" ]]; then

        printf 'Error: invalid module metadata: %s\n' \
            "$requested_module" >&2

        reset_module_contract
        return 1
    fi

    if capability_output="$(module_capabilities)"; then
        :
    else
        reset_module_contract
        return 1
    fi

    LWBS_MODULE_CAPABILITIES=()

    while IFS= read -r capability; do
        [[ -z "$capability" ]] && continue

        if [[ ! "$capability" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
            printf 'Error: invalid capability declaration in module %s: %s\n' \
                "$requested_module" \
                "$capability" >&2

            reset_module_contract
            return 1
        fi

        LWBS_MODULE_CAPABILITIES+=("$capability")
    done <<<"$capability_output"

    LWBS_MODULE_DEPENDENCIES=()

    if declare -F module_dependencies >/dev/null 2>&1; then
        if dependency_output="$(module_dependencies)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r dependency; do
            [[ -z "$dependency" ]] && continue

            if [[ ! "$dependency" =~ ^[a-z0-9][a-z0-9_-]*$ ||
                "$dependency" == "$requested_module" ||
                -n "${seen_dependencies[$dependency]+defined}" ]]; then

                printf 'Error: invalid dependency in module %s: %s\n' \
                    "$requested_module" \
                    "$dependency" >&2

                reset_module_contract
                return 1
            fi

            seen_dependencies["$dependency"]=1
            LWBS_MODULE_DEPENDENCIES+=("$dependency")
        done <<<"$dependency_output"
    fi

    LWBS_MODULE_CONFLICTS=()

    if declare -F module_conflicts >/dev/null 2>&1; then
        if conflict_output="$(module_conflicts)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r conflict; do
            [[ -z "$conflict" ]] && continue

            if [[ ! "$conflict" =~ ^[a-z0-9][a-z0-9_-]*$ ||
                "$conflict" == "$requested_module" ||
                -n "${seen_conflicts[$conflict]+defined}" ||
                -n "${seen_dependencies[$conflict]+defined}" ]]; then

                printf 'Error: invalid conflict in module %s: %s\n' \
                    "$requested_module" \
                    "$conflict" >&2

                reset_module_contract
                return 1
            fi

            seen_conflicts["$conflict"]=1
            LWBS_MODULE_CONFLICTS+=("$conflict")
        done <<<"$conflict_output"
    fi

    LWBS_MODULE_EXTERNAL_INSTALLERS=()

    if declare -F module_external_installers >/dev/null 2>&1; then
        if external_output="$(module_external_installers)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r installer_id; do
            [[ -z "$installer_id" ]] && continue

            if [[ ! "$installer_id" =~ ^[a-z0-9][a-z0-9_-]*$ ||
                -n "${seen_external_installers[$installer_id]+defined}" ]]; then

                printf 'Error: invalid external installer in module %s: %s\n' \
                    "$requested_module" \
                    "$installer_id" >&2

                reset_module_contract
                return 1
            fi

            seen_external_installers["$installer_id"]=1
            LWBS_MODULE_EXTERNAL_INSTALLERS+=("$installer_id")
        done <<<"$external_output"
    fi

    LWBS_MODULE_SERVICES=()

    if declare -F module_services >/dev/null 2>&1; then
        if service_output="$(module_services)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r service_requirement; do
            [[ -z "$service_requirement" ]] && continue

            if ! parse_service_requirement \
                "$service_requirement" \
                service_name \
                enabled_state \
                active_state \
                restart_policy; then

                reset_module_contract
                return 1
            fi

            if [[ -n "${seen_services[$service_name]+defined}" ]]; then
                printf 'Error: duplicate service requirement in module %s: %s\n' \
                    "$requested_module" \
                    "$service_name" >&2

                reset_module_contract
                return 1
            fi

            seen_services["$service_name"]=1

            LWBS_MODULE_SERVICES+=(
                "$service_name $enabled_state $active_state $restart_policy"
            )
        done <<<"$service_output"
    fi

    LWBS_MODULE_CONFIGURATIONS=()

    if declare -F module_configurations >/dev/null 2>&1; then
        if configuration_output="$(module_configurations)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r configuration_requirement; do
            [[ -z "$configuration_requirement" ]] && continue

            if ! parse_configuration_requirement \
                "$configuration_requirement" \
                configuration_id \
                configuration_kind \
                configuration_scope \
                configuration_destination \
                configuration_source \
                configuration_mode \
                configuration_backup; then

                reset_module_contract
                return 1
            fi

            if [[ -n "${seen_configurations[$configuration_id]+defined}" ]]; then
                printf 'Error: duplicate configuration in module %s: %s\n' \
                    "$requested_module" \
                    "$configuration_id" >&2

                reset_module_contract
                return 1
            fi

            seen_configurations["$configuration_id"]=1
            LWBS_MODULE_CONFIGURATIONS+=("$configuration_requirement")
        done <<<"$configuration_output"
    fi

    LWBS_MODULE_GROUP_MEMBERSHIPS=()

    if declare -F module_group_memberships >/dev/null 2>&1; then
        if group_output="$(module_group_memberships)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r group_name; do
            [[ -z "$group_name" ]] && continue

            if [[ ! "$group_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                printf 'Error: invalid group requirement in module %s: %s\n' \
                    "$requested_module" \
                    "$group_name" >&2

                reset_module_contract
                return 1
            fi

            if [[ -n "${seen_groups[$group_name]+defined}" ]]; then
                printf 'Error: duplicate group requirement in module %s: %s\n' \
                    "$requested_module" \
                    "$group_name" >&2

                reset_module_contract
                return 1
            fi

            seen_groups["$group_name"]=1
            LWBS_MODULE_GROUP_MEMBERSHIPS+=("$group_name")
        done <<<"$group_output"
    fi

    LWBS_MODULE_RESTART_REQUIREMENTS=()

    if declare -F module_restart_requirements >/dev/null 2>&1; then
        if restart_output="$(module_restart_requirements)"; then
            :
        else
            reset_module_contract
            return 1
        fi

        while IFS= read -r restart_requirement; do
            [[ -z "$restart_requirement" ]] && continue

            if ! parse_restart_requirement \
                "$restart_requirement" \
                restart_type \
                restart_target \
                restart_reason; then

                reset_module_contract
                return 1
            fi

            restart_requirement="$restart_type|$restart_target|$restart_reason"

            if [[ -n "${seen_restart_requirements[$restart_requirement]+defined}" ]]; then
                continue
            fi

            seen_restart_requirements["$restart_requirement"]=1
            LWBS_MODULE_RESTART_REQUIREMENTS+=("$restart_requirement")
        done <<<"$restart_output"
    fi

    if ((${#LWBS_MODULE_CAPABILITIES[@]} == 0 && \
        ${#LWBS_MODULE_DEPENDENCIES[@]} == 0 && \
        ${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]} == 0 && \
        ${#LWBS_MODULE_SERVICES[@]} == 0 && \
        ${#LWBS_MODULE_CONFIGURATIONS[@]} == 0 && \
        ${#LWBS_MODULE_GROUP_MEMBERSHIPS[@]} == 0)) &&
            ! declare -F module_apply >/dev/null 2>&1 &&
            ! declare -F module_verify >/dev/null 2>&1; then

        printf 'Error: module %s does not declare any actions or dependencies.\n' \
            "$requested_module" >&2

        reset_module_contract
        return 1
    fi

    LWBS_MODULE_PATH="$module_path"

    log_info \
        "Module loaded: id=$LWBS_MODULE_ID capability_count=${#LWBS_MODULE_CAPABILITIES[@]} dependency_count=${#LWBS_MODULE_DEPENDENCIES[@]} conflict_count=${#LWBS_MODULE_CONFLICTS[@]} external_count=${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]} service_count=${#LWBS_MODULE_SERVICES[@]} configuration_count=${#LWBS_MODULE_CONFIGURATIONS[@]} group_count=${#LWBS_MODULE_GROUP_MEMBERSHIPS[@]} restart_count=${#LWBS_MODULE_RESTART_REQUIREMENTS[@]}"

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

collect_missing_module_packages() {
    local result_name="${1:-}"
    local package
    local package_state
    local exit_code

    if [[ -z "$result_name" ||
        ! "$result_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then

        return 2
    fi

    shift

    local -n output_array_ref="$result_name"

    output_array_ref=()

    for package in "$@"; do
        if package_state="$(distro_package_state "$package")"; then
            :
        else
            exit_code=$?
            return "$exit_code"
        fi

        case "$package_state" in
            installed)
                printf '    - %s [installed, skip]\n' "$package"
                ;;

            absent)
                printf '    - %s [missing]\n' "$package"
                output_array_ref+=("$package")
                ;;

            *)
                return 1
                ;;
        esac
    done

    return 0
}

execute_loaded_module() {
    local installer_id
    local exit_code

    local -a resolved_packages=()
    local -a missing_packages=()

    if [[ -z "$LWBS_MODULE_ID" ]]; then
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ||
        -z "${LWBS_CAPABILITY_PROFILE:-}" ]]; then

        return 1
    fi

    if ((${#LWBS_MODULE_SERVICES[@]} > 0 || \
        ${#LWBS_MODULE_CONFIGURATIONS[@]} > 0 || \
        ${#LWBS_MODULE_GROUP_MEMBERSHIPS[@]} > 0)); then

        printf 'Error: managed services, configurations, and group memberships require the planning framework.\n' \
            >&2

        return 1
    fi

    if ((${#LWBS_MODULE_CAPABILITIES[@]} > 0)); then
        resolve_capabilities \
            resolved_packages \
            "${LWBS_MODULE_CAPABILITIES[@]}" || return $?

        collect_missing_module_packages \
            missing_packages \
            "${resolved_packages[@]}" || return $?

        if ((${#missing_packages[@]} > 0)); then
            distro_install_packages "${missing_packages[@]}"
        fi
    fi

    for installer_id in "${LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"; do
        if run_external_installer "$installer_id"; then
            reset_external_installer_contract
        else
            exit_code=$?
            reset_external_installer_contract
            return "$exit_code"
        fi
    done

    if declare -F module_apply >/dev/null 2>&1; then
        module_apply
    fi
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
        module_dependencies \
        module_conflicts \
        module_external_installers \
        module_services \
        module_configurations \
        module_group_memberships \
        module_restart_requirements \
        module_preflight_requirements \
        module_apply \
        module_verify \
        2>/dev/null || true

    LWBS_MODULE_ID=""
    LWBS_MODULE_NAME=""
    LWBS_MODULE_DESCRIPTION=""
    LWBS_MODULE_PATH=""

    LWBS_MODULE_CAPABILITIES=()
    LWBS_MODULE_DEPENDENCIES=()
    LWBS_MODULE_CONFLICTS=()
    LWBS_MODULE_EXTERNAL_INSTALLERS=()
    LWBS_MODULE_SERVICES=()
    LWBS_MODULE_CONFIGURATIONS=()
    LWBS_MODULE_GROUP_MEMBERSHIPS=()
    LWBS_MODULE_RESTART_REQUIREMENTS=()
}
