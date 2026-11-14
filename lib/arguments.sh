#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Command-line argument handling.
# This file:
# 1. Parses supported command-line options.
# 2. Stores distribution and workstation profile selections.
# 3. Stores explicit module additions and exclusions.
# 4. Rejects conflicting or duplicate module selections.
# 5. Rejects unknown or incomplete option syntax before bootstrap processing.

LWBS_DRY_RUN=false
LWBS_ASSUME_YES=false
LWBS_REQUESTED_DISTRO_PROFILE=""
LWBS_REQUESTED_WORKSTATION_PROFILE=""
LWBS_CLI_ACTION="run"

declare -a LWBS_REQUESTED_MODULES=()
declare -a LWBS_EXCLUDED_MODULES=()

validate_cli_selection_id() {
    local selection_id="${1:-}"

    [[ "$selection_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

cli_array_contains() {
    local array_name="${1:-}"
    local expected_value="${2:-}"
    local value

    local -n array_ref="$array_name"

    for value in "${array_ref[@]}"; do
        if [[ "$value" == "$expected_value" ]]; then
            return 0
        fi
    done

    return 1
}

append_unique_cli_selection() {
    local array_name="${1:-}"
    local value="${2:-}"
    local option_name="${3:-}"

    local -n array_ref="$array_name"

    if cli_array_contains "$array_name" "$value"; then
        printf 'Error: duplicate %s selection: %s\n' \
            "$option_name" \
            "$value" >&2
        return 2
    fi

    array_ref+=("$value")

    return 0
}

validate_cli_module_selection_conflicts() {
    local requested_module
    local excluded_module

    for requested_module in "${LWBS_REQUESTED_MODULES[@]}"; do
        for excluded_module in "${LWBS_EXCLUDED_MODULES[@]}"; do
            if [[ "$requested_module" == "$excluded_module" ]]; then
                printf 'Error: module cannot be both included and excluded: %s\n' \
                    "$requested_module" >&2
                return 2
            fi
        done
    done

    return 0
}

parse_arguments() {
    local distro_value
    local profile_value
    local module_value
    local exclusion_value

    LWBS_DRY_RUN=false
    LWBS_ASSUME_YES=false
    LWBS_REQUESTED_DISTRO_PROFILE=""
    LWBS_REQUESTED_WORKSTATION_PROFILE=""
    LWBS_CLI_ACTION="run"
    LWBS_REQUESTED_MODULES=()
    LWBS_EXCLUDED_MODULES=()

    while (($# > 0)); do
        case "$1" in
            --dry-run)
                LWBS_DRY_RUN=true
                ;;

            -y | --yes)
                # Explicitly approve supported non-interactive confirmations,
                # including detected distro selection and execution plans.
                LWBS_ASSUME_YES=true
                ;;

            --distro)
                if (($# < 2)) || [[ -z "${2:-}" || "$2" == -* ]]; then
                    printf 'Error: %s requires a distribution profile.\n' \
                        "$1" >&2
                    return 2
                fi

                LWBS_REQUESTED_DISTRO_PROFILE="${2,,}"
                shift
                ;;

            --distro=*)
                distro_value="${1#*=}"

                if [[ -z "$distro_value" ]]; then
                    printf 'Error: --distro requires a distribution profile.\n' \
                        >&2
                    return 2
                fi

                LWBS_REQUESTED_DISTRO_PROFILE="${distro_value,,}"
                ;;

            --profile)
                if (($# < 2)) || [[ -z "${2:-}" || "$2" == -* ]]; then
                    printf 'Error: %s requires a workstation profile.\n' \
                        "$1" >&2
                    return 2
                fi

                profile_value="${2,,}"

                if ! validate_cli_selection_id "$profile_value"; then
                    printf 'Error: invalid workstation profile ID: %s\n' \
                        "$profile_value" >&2
                    return 2
                fi

                LWBS_REQUESTED_WORKSTATION_PROFILE="$profile_value"
                shift
                ;;

            --profile=*)
                profile_value="${1#*=}"
                profile_value="${profile_value,,}"

                if [[ -z "$profile_value" ]] ||
                    ! validate_cli_selection_id "$profile_value"; then

                    printf 'Error: --profile requires a valid workstation profile.\n' \
                        >&2
                    return 2
                fi

                LWBS_REQUESTED_WORKSTATION_PROFILE="$profile_value"
                ;;

            --module)
                if (($# < 2)) || [[ -z "${2:-}" || "$2" == -* ]]; then
                    printf 'Error: %s requires a module ID.\n' \
                        "$1" >&2
                    return 2
                fi

                module_value="${2,,}"

                if ! validate_cli_selection_id "$module_value"; then
                    printf 'Error: invalid module ID: %s\n' \
                        "$module_value" >&2
                    return 2
                fi

                append_unique_cli_selection \
                    LWBS_REQUESTED_MODULES \
                    "$module_value" \
                    "--module" || return $?

                shift
                ;;

            --module=*)
                module_value="${1#*=}"
                module_value="${module_value,,}"

                if [[ -z "$module_value" ]] ||
                    ! validate_cli_selection_id "$module_value"; then

                    printf 'Error: --module requires a valid module ID.\n' \
                        >&2
                    return 2
                fi

                append_unique_cli_selection \
                    LWBS_REQUESTED_MODULES \
                    "$module_value" \
                    "--module" || return $?
                ;;

            --exclude-module)
                if (($# < 2)) || [[ -z "${2:-}" || "$2" == -* ]]; then
                    printf 'Error: %s requires a module ID.\n' \
                        "$1" >&2
                    return 2
                fi

                exclusion_value="${2,,}"

                if ! validate_cli_selection_id "$exclusion_value"; then
                    printf 'Error: invalid excluded module ID: %s\n' \
                        "$exclusion_value" >&2
                    return 2
                fi

                append_unique_cli_selection \
                    LWBS_EXCLUDED_MODULES \
                    "$exclusion_value" \
                    "--exclude-module" || return $?

                shift
                ;;

            --exclude-module=*)
                exclusion_value="${1#*=}"
                exclusion_value="${exclusion_value,,}"

                if [[ -z "$exclusion_value" ]] ||
                    ! validate_cli_selection_id "$exclusion_value"; then

                    printf 'Error: --exclude-module requires a valid module ID.\n' \
                        >&2
                    return 2
                fi

                append_unique_cli_selection \
                    LWBS_EXCLUDED_MODULES \
                    "$exclusion_value" \
                    "--exclude-module" || return $?
                ;;

            --list-profiles)
                LWBS_CLI_ACTION="list-profiles"
                ;;

            -h | --help)
                LWBS_CLI_ACTION="help"
                ;;

            --version)
                LWBS_CLI_ACTION="version"
                ;;

            -*)
                printf 'Error: unknown option: %s\n' "$1" >&2
                return 2
                ;;

            *)
                printf 'Error: unexpected argument: %s\n' "$1" >&2
                return 2
                ;;
        esac

        shift
    done

    validate_cli_module_selection_conflicts
}
