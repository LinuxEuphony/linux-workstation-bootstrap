#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# User configuration handling.
# Provides a safe, deterministic way to override supported application
# defaults without modifying repository-managed configuration files.
#
# Configuration precedence:
#
#   repository defaults
#       -> user configuration
#       -> command-line arguments
#
# User configuration is parsed as data. The file is never sourced as shell
# code, preventing configuration values from becoming arbitrary execution.
#
# Supported settings:
#
#   distro_profile=auto|<supported-distro>
#
# Additional settings should only be introduced when the corresponding
# application behaviour exists and can be validated safely.

LWBS_USER_CONFIG_PATH=""
LWBS_CONFIG_DISTRO_PROFILE="$LWBS_DEFAULT_DISTRO_PROFILE"

# Resolve the location of the optional user configuration file.
resolve_user_config_path() {
    local config_root

    # Primarily used by automated tests and controlled embedding scenarios.
    if [[ -n "${LWBS_USER_CONFIG_PATH_OVERRIDE:-}" ]]; then
        printf '%s\n' "$LWBS_USER_CONFIG_PATH_OVERRIDE"
        return 0
    fi

    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        config_root="$XDG_CONFIG_HOME"
    elif [[ -n "${HOME:-}" ]]; then
        config_root="$HOME/.config"
    else
        printf 'Error: unable to determine the user configuration directory.\n' \
            >&2
        return 1
    fi

    printf '%s/%s/%s\n' \
        "$config_root" \
        "$LWBS_CONFIG_DIRECTORY_NAME" \
        "$LWBS_CONFIG_FILE_NAME"
}

# Trim leading and trailing whitespace from a string.
trim_config_value() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s\n' "$value"
}

# Validate and store one supported user configuration value.
apply_user_config_value() {
    local key="${1:-}"
    local value="${2:-}"

    case "$key" in
        distro_profile)
            value="${value,,}"

            if [[ "$value" == "auto" ]]; then
                LWBS_CONFIG_DISTRO_PROFILE="auto"
                return 0
            fi

            if ! is_supported_distro "$value"; then
                printf 'Error: unsupported distro_profile in user configuration: %s\n' \
                    "$value" >&2

                return 1
            fi

            LWBS_CONFIG_DISTRO_PROFILE="$value"
            ;;

        *)
            printf 'Error: unsupported user configuration setting: %s\n' \
                "$key" >&2

            return 1
            ;;
    esac

    return 0
}

# Load the optional user-local configuration file.
load_user_config() {
    local config_path
    local line
    local key
    local value
    local line_number=0

    local -A seen_keys=()

    # Start from repository defaults for every bootstrap invocation.
    LWBS_CONFIG_DISTRO_PROFILE="$LWBS_DEFAULT_DISTRO_PROFILE"
    LWBS_USER_CONFIG_PATH=""

    if config_path="$(resolve_user_config_path)"; then
        :
    else
        return $?
    fi

    LWBS_USER_CONFIG_PATH="$config_path"

    # User configuration is optional.
    if [[ ! -e "$config_path" ]]; then
        log_info \
            "User configuration not present; repository defaults will be used."

        return 0
    fi

    if [[ ! -f "$config_path" ]]; then
        printf 'Error: user configuration path is not a regular file: %s\n' \
            "$config_path" >&2

        log_error \
            "User configuration path is not a regular file: $config_path"

        return 1
    fi

    if [[ ! -r "$config_path" ]]; then
        printf 'Error: user configuration file is not readable: %s\n' \
            "$config_path" >&2

        log_error \
            "User configuration file is not readable: $config_path"

        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))

        line="$(trim_config_value "$line")"

        # Ignore empty lines and full-line comments.
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        if [[ "$line" != *=* ]]; then
            printf 'Error: invalid user configuration syntax at line %d.\n' \
                "$line_number" >&2

            log_error \
                "Invalid user configuration syntax: path=$config_path line=$line_number"

            return 1
        fi

        key="$(trim_config_value "${line%%=*}")"
        value="$(trim_config_value "${line#*=}")"

        if [[ ! "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
            printf 'Error: invalid user configuration key at line %d: %s\n' \
                "$line_number" \
                "$key" >&2

            log_error \
                "Invalid user configuration key: path=$config_path line=$line_number key=$key"

            return 1
        fi

        if [[ -z "$value" ]]; then
            printf 'Error: empty user configuration value at line %d: %s\n' \
                "$line_number" \
                "$key" >&2

            log_error \
                "Empty user configuration value: path=$config_path line=$line_number key=$key"

            return 1
        fi

        if [[ -n "${seen_keys[$key]+defined}" ]]; then
            printf 'Error: duplicate user configuration setting at line %d: %s\n' \
                "$line_number" \
                "$key" >&2

            log_error \
                "Duplicate user configuration setting: path=$config_path line=$line_number key=$key"

            return 1
        fi

        seen_keys["$key"]=1

        if ! apply_user_config_value "$key" "$value"; then
            log_error \
                "Invalid user configuration value: path=$config_path line=$line_number key=$key"

            return 1
        fi
    done <"$config_path"

    log_info "User configuration loaded: $config_path"
    log_info \
        "Configured default distribution profile: $LWBS_CONFIG_DISTRO_PROFILE"

    return 0
}