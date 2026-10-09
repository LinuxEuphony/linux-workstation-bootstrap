#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# External software installation framework.
# Provides a controlled path for software that is not installed exclusively
# from the selected distribution's standard package repositories.
#
# This file:
# 1. Loads software-specific installer definitions.
# 2. Validates external installer contracts and installation methods.
# 3. Requires explicit installed-state detection for idempotent execution.
# 4. Skips external installation when the requested software is satisfied.
# 5. Provides predictable temporary staging for downloaded artifacts.
# 6. Provides controlled helpers for downloads, local packages, archives,
#    repository files, and installer scripts.
# 7. Routes commands through the shared execution layer.
# 8. Preserves dry-run behaviour.

LWBS_EXTERNAL_ID=""
LWBS_EXTERNAL_NAME=""
LWBS_EXTERNAL_DESCRIPTION=""
LWBS_EXTERNAL_METHOD=""
LWBS_EXTERNAL_PATH=""
LWBS_EXTERNAL_STAGE_DIR=""

declare -ar LWBS_EXTERNAL_METHODS=(
    "repository"
    "package"
    "archive"
    "script"
)

load_external_installer() {
    local requested_installer="${1:-}"
    local installer_directory
    local installer_path

    if [[ -z "$requested_installer" ]]; then
        printf 'Error: no external installer was provided.\n' >&2
        log_error "External installer load requested without an installer ID."
        return 2
    fi

    if [[ ! "$requested_installer" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid external installer ID: %s\n' \
            "$requested_installer" >&2

        log_error \
            "Invalid external installer ID requested: $requested_installer"

        return 2
    fi

    installer_directory="${LWBS_EXTERNAL_INSTALLERS_DIR_OVERRIDE:-$LWBS_ROOT/installers}"
    installer_path="$installer_directory/$requested_installer.sh"

    if [[ ! -r "$installer_path" ]]; then
        printf 'Error: external installer not found: %s\n' \
            "$installer_path" >&2

        log_error \
            "External installer file not found: installer=$requested_installer path=$installer_path"

        return 1
    fi

    reset_external_installer_contract

    log_info "Loading external installer: $requested_installer"

    # shellcheck disable=SC1090
    if ! source "$installer_path"; then
        printf 'Error: failed to load external installer: %s\n' \
            "$requested_installer" >&2

        log_error \
            "External installer source failed: installer=$requested_installer path=$installer_path"

        reset_external_installer_contract
        return 1
    fi

    if ! validate_external_installer_contract; then
        log_error \
            "External installer contract validation failed: $requested_installer"

        reset_external_installer_contract
        return 1
    fi

    LWBS_EXTERNAL_ID="$(external_id)"
    LWBS_EXTERNAL_NAME="$(external_name)"
    LWBS_EXTERNAL_DESCRIPTION="$(external_description)"
    LWBS_EXTERNAL_METHOD="$(external_method)"

    if [[ -z "$LWBS_EXTERNAL_ID" ]]; then
        printf 'Error: external installer returned an empty installer ID.\n' >&2
        reset_external_installer_contract
        return 1
    fi

    if [[ "$LWBS_EXTERNAL_ID" != "$requested_installer" ]]; then
        printf 'Error: external installer ID mismatch: requested %s, installer declared %s\n' \
            "$requested_installer" \
            "$LWBS_EXTERNAL_ID" >&2

        log_error \
            "External installer ID mismatch: requested=$requested_installer declared=$LWBS_EXTERNAL_ID"

        reset_external_installer_contract
        return 1
    fi

    if [[ -z "$LWBS_EXTERNAL_NAME" ]]; then
        printf 'Error: external installer returned an empty display name: %s\n' \
            "$requested_installer" >&2

        reset_external_installer_contract
        return 1
    fi

    if [[ -z "$LWBS_EXTERNAL_DESCRIPTION" ]]; then
        printf 'Error: external installer returned an empty description: %s\n' \
            "$requested_installer" >&2

        reset_external_installer_contract
        return 1
    fi

    if ! is_supported_external_method "$LWBS_EXTERNAL_METHOD"; then
        printf 'Error: unsupported external installation method "%s" for installer "%s".\n' \
            "$LWBS_EXTERNAL_METHOD" \
            "$requested_installer" >&2

        log_error \
            "Unsupported external installation method: installer=$requested_installer method=$LWBS_EXTERNAL_METHOD"

        reset_external_installer_contract
        return 1
    fi

    if ! validate_external_method_contract "$LWBS_EXTERNAL_METHOD"; then
        log_error \
            "External installer method contract validation failed: installer=$requested_installer method=$LWBS_EXTERNAL_METHOD"

        reset_external_installer_contract
        return 1
    fi

    LWBS_EXTERNAL_PATH="$installer_path"

    log_info \
        "External installer loaded: id=$LWBS_EXTERNAL_ID method=$LWBS_EXTERNAL_METHOD"

    return 0
}

validate_external_installer_contract() {
    local required_function

    local -a required_functions=(
        "external_id"
        "external_name"
        "external_description"
        "external_method"
        "external_state"
    )

    for required_function in "${required_functions[@]}"; do
        if ! declare -F "$required_function" >/dev/null 2>&1; then
            printf 'Error: external installer is missing required function: %s\n' \
                "$required_function" >&2

            return 1
        fi
    done

    return 0
}

is_supported_external_method() {
    local requested_method="${1:-}"
    local supported_method

    for supported_method in "${LWBS_EXTERNAL_METHODS[@]}"; do
        if [[ "$requested_method" == "$supported_method" ]]; then
            return 0
        fi
    done

    return 1
}

validate_external_method_contract() {
    local method="${1:-}"
    local required_function

    required_function="external_${method}_apply"

    if ! declare -F "$required_function" >/dev/null 2>&1; then
        printf 'Error: external installer method "%s" requires function: %s\n' \
            "$method" \
            "$required_function" >&2

        return 1
    fi

    return 0
}

# Query the current state reported by the loaded external installer.
#
# The installer must return one of:
#   installed
#   absent
#
# Any non-zero return code means the state could not be determined.
query_external_installation_state() {
    local installation_state
    local exit_code

    if [[ -z "$LWBS_EXTERNAL_ID" ]]; then
        printf 'Error: no external installer is currently loaded.\n' >&2
        return 2
    fi

    if installation_state="$(external_state)"; then
        :
    else
        exit_code=$?

        printf 'Error: unable to determine external software state: %s\n' \
            "$LWBS_EXTERNAL_ID" >&2

        log_error \
            "External software state check failed: installer=$LWBS_EXTERNAL_ID exit_code=$exit_code"

        return "$exit_code"
    fi

    case "$installation_state" in
        installed | absent)
            printf '%s\n' "$installation_state"
            return 0
            ;;

        *)
            printf 'Error: external installer "%s" returned invalid state "%s".\n' \
                "$LWBS_EXTERNAL_ID" \
                "$installation_state" >&2

            log_error \
                "Invalid external software state: installer=$LWBS_EXTERNAL_ID state=$installation_state"

            return 1
            ;;
    esac
}

execute_loaded_external_installer() {
    local apply_function
    local installation_state
    local apply_exit_code=0
    local cleanup_exit_code=0
    local validation_exit_code
    local state_exit_code

    if [[ -z "$LWBS_EXTERNAL_ID" ]]; then
        printf 'Error: no external installer is currently loaded.\n' >&2
        log_error "External installer execution requested without a loaded installer."
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ]]; then
        printf 'Error: a distribution adapter must be loaded before executing external installers.\n' \
            >&2

        log_error \
            "External installer execution requested without a distro adapter: installer=$LWBS_EXTERNAL_ID"

        return 1
    fi

    printf '\nExternal software: %s\n' "$LWBS_EXTERNAL_NAME"
    printf '  ID          : %s\n' "$LWBS_EXTERNAL_ID"
    printf '  Description : %s\n' "$LWBS_EXTERNAL_DESCRIPTION"
    printf '  Method      : %s\n' "$LWBS_EXTERNAL_METHOD"

    log_info \
        "Evaluating external installer: id=$LWBS_EXTERNAL_ID method=$LWBS_EXTERNAL_METHOD"

    if installation_state="$(query_external_installation_state)"; then
        :
    else
        state_exit_code=$?
        return "$state_exit_code"
    fi

    if [[ "$installation_state" == "installed" ]]; then
        printf '  Status      : already installed\n'
        printf '  Action      : skip\n'

        log_info \
            "External installer skipped because software is already installed: $LWBS_EXTERNAL_ID"

        return 0
    fi

    printf '  Status      : not installed\n'

    # Installation-specific requirements are evaluated only when an
    # installation is actually necessary.
    if declare -F external_validate_environment >/dev/null 2>&1; then
        if external_validate_environment; then
            :
        else
            validation_exit_code=$?

            log_error \
                "External installer environment validation failed: installer=$LWBS_EXTERNAL_ID exit_code=$validation_exit_code"

            return "$validation_exit_code"
        fi
    fi

    if ! prepare_external_staging; then
        log_error \
            "Unable to prepare external installer staging: $LWBS_EXTERNAL_ID"

        return 1
    fi

    apply_function="external_${LWBS_EXTERNAL_METHOD}_apply"

    if "$apply_function"; then
        apply_exit_code=0
    else
        apply_exit_code=$?

        log_error \
            "External installation failed: installer=$LWBS_EXTERNAL_ID method=$LWBS_EXTERNAL_METHOD exit_code=$apply_exit_code"
    fi

    if cleanup_external_staging; then
        cleanup_exit_code=0
    else
        cleanup_exit_code=$?

        log_error \
            "External installer staging cleanup failed: installer=$LWBS_EXTERNAL_ID exit_code=$cleanup_exit_code"
    fi

    if ((apply_exit_code != 0)); then
        return "$apply_exit_code"
    fi

    if ((cleanup_exit_code != 0)); then
        return "$cleanup_exit_code"
    fi

    if "$LWBS_DRY_RUN"; then
        log_info \
            "Dry-run external installer completed: $LWBS_EXTERNAL_ID"
    else
        log_info \
            "External installer completed successfully: $LWBS_EXTERNAL_ID"
    fi

    return 0
}

run_external_installer() {
    local installer_id="${1:-}"
    local exit_code

    if load_external_installer "$installer_id"; then
        :
    else
        exit_code=$?
        return "$exit_code"
    fi

    execute_loaded_external_installer
}

prepare_external_staging() {
    local temp_root

    if [[ -n "$LWBS_EXTERNAL_STAGE_DIR" ]]; then
        return 0
    fi

    temp_root="${TMPDIR:-/tmp}"

    if "$LWBS_DRY_RUN"; then
        LWBS_EXTERNAL_STAGE_DIR="$temp_root/${LWBS_APP_SLUG}-external-dry-run"

        log_info \
            "Dry-run external staging path prepared: installer=$LWBS_EXTERNAL_ID"

        return 0
    fi

    if [[ ! -d "$temp_root" || ! -w "$temp_root" ]]; then
        printf 'Error: external staging root is not writable: %s\n' \
            "$temp_root" >&2

        return 1
    fi

    if ! LWBS_EXTERNAL_STAGE_DIR="$(
        mktemp -d "$temp_root/${LWBS_APP_SLUG}-external.XXXXXX"
    )"; then
        printf 'Error: unable to create external installation staging directory.\n' \
            >&2
        return 1
    fi

    chmod 700 -- "$LWBS_EXTERNAL_STAGE_DIR"

    log_info \
        "External installer staging created: installer=$LWBS_EXTERNAL_ID"

    return 0
}

cleanup_external_staging() {
    local stage_directory="$LWBS_EXTERNAL_STAGE_DIR"

    LWBS_EXTERNAL_STAGE_DIR=""

    if [[ -z "$stage_directory" ]]; then
        return 0
    fi

    if "$LWBS_DRY_RUN"; then
        log_info \
            "Dry-run external staging cleanup completed: installer=$LWBS_EXTERNAL_ID"

        return 0
    fi

    if [[ ! -d "$stage_directory" ]]; then
        return 0
    fi

    if run_command rm -rf -- "$stage_directory"; then
        return 0
    fi

    printf 'Error: unable to clean external installer staging directory.\n' \
        >&2

    return 1
}

external_stage_path() {
    local filename="${1:-}"

    if [[ -z "$LWBS_EXTERNAL_STAGE_DIR" ]]; then
        printf 'Error: external installer staging has not been prepared.\n' >&2
        return 1
    fi

    if [[ -z "$filename" ||
        ! "$filename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        printf 'Error: invalid external staging filename: %s\n' \
            "$filename" >&2

        return 2
    fi

    printf '%s/%s\n' \
        "$LWBS_EXTERNAL_STAGE_DIR" \
        "$filename"
}

external_download() {
    local url="${1:-}"
    local destination="${2:-}"

    if [[ -z "$url" || -z "$destination" ]]; then
        printf 'Error: external download requires a URL and destination.\n' \
            >&2
        return 2
    fi

    if [[ ! "$url" =~ ^https://[^[:space:]]+$ ]]; then
        printf 'Error: external download URL must use HTTPS.\n' >&2

        log_error \
            "Rejected non-HTTPS external download: installer=$LWBS_EXTERNAL_ID"

        return 1
    fi

    if [[ "$destination" != /* ]]; then
        printf 'Error: external download destination must be an absolute path.\n' \
            >&2
        return 2
    fi

    if ! require_command curl; then
        log_error \
            "External installer requires curl: installer=$LWBS_EXTERNAL_ID"
        return 1
    fi

    log_info \
        "Downloading external artifact: installer=$LWBS_EXTERNAL_ID"

    run_command \
        curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --output "$destination" \
        "$url"
}

external_install_local_package() {
    local package_file="${1:-}"

    if [[ -z "$package_file" ]]; then
        printf 'Error: no local package file was provided.\n' >&2
        return 2
    fi

    if [[ "$package_file" != /* ]]; then
        printf 'Error: local package path must be absolute.\n' >&2
        return 2
    fi

    if ! declare -F distro_install_local_package >/dev/null 2>&1; then
        printf 'Error: the loaded distribution adapter cannot install local packages.\n' \
            >&2

        return 1
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$package_file" ]]; then
        printf 'Error: local package file not found: %s\n' \
            "$package_file" >&2

        return 1
    fi

    distro_install_local_package "$package_file"
}

external_install_system_file() {
    local source_file="${1:-}"
    local destination="${2:-}"
    local mode="${3:-0644}"

    if [[ -z "$source_file" || -z "$destination" ]]; then
        printf 'Error: system file installation requires source and destination paths.\n' \
            >&2
        return 2
    fi

    if [[ "$source_file" != /* || "$destination" != /* ]]; then
        printf 'Error: system file installation paths must be absolute.\n' \
            >&2
        return 2
    fi

    if [[ ! "$mode" =~ ^0?[0-7]{3,4}$ ]]; then
        printf 'Error: invalid system file mode: %s\n' \
            "$mode" >&2
        return 2
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$source_file" ]]; then
        printf 'Error: source file not found: %s\n' \
            "$source_file" >&2
        return 1
    fi

    run_privileged_command \
        install \
        -D \
        -m "$mode" \
        -- "$source_file" "$destination"
}

external_extract_tar_archive() {
    local archive_file="${1:-}"
    local destination="${2:-}"
    local exit_code

    if [[ -z "$archive_file" || -z "$destination" ]]; then
        printf 'Error: archive extraction requires an archive and destination.\n' \
            >&2
        return 2
    fi

    if [[ "$archive_file" != /* || "$destination" != /* ]]; then
        printf 'Error: archive and destination paths must be absolute.\n' \
            >&2
        return 2
    fi

    if ! require_command tar; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$archive_file" ]]; then
        printf 'Error: archive file not found: %s\n' \
            "$archive_file" >&2
        return 1
    fi

    if run_command mkdir -p -- "$destination"; then
        :
    else
        exit_code=$?
        return "$exit_code"
    fi

    run_command \
        tar \
        -xf "$archive_file" \
        -C "$destination"
}

external_extract_zip_archive() {
    local archive_file="${1:-}"
    local destination="${2:-}"
    local exit_code

    if [[ -z "$archive_file" || -z "$destination" ]]; then
        printf 'Error: ZIP extraction requires an archive and destination.\n' \
            >&2
        return 2
    fi

    if [[ "$archive_file" != /* || "$destination" != /* ]]; then
        printf 'Error: archive and destination paths must be absolute.\n' \
            >&2
        return 2
    fi

    if ! require_command unzip; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$archive_file" ]]; then
        printf 'Error: ZIP archive file not found: %s\n' \
            "$archive_file" >&2
        return 1
    fi

    if run_command mkdir -p -- "$destination"; then
        :
    else
        exit_code=$?
        return "$exit_code"
    fi

    run_command \
        unzip \
        -q \
        "$archive_file" \
        -d "$destination"
}

external_run_script_file() {
    local interpreter="${1:-}"
    local script_file="${2:-}"

    if [[ -z "$interpreter" || -z "$script_file" ]]; then
        printf 'Error: script execution requires an interpreter and script file.\n' \
            >&2
        return 2
    fi

    if [[ ! "$interpreter" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
        printf 'Error: invalid installer script interpreter: %s\n' \
            "$interpreter" >&2
        return 2
    fi

    if [[ "$script_file" != /* ]]; then
        printf 'Error: installer script path must be absolute.\n' >&2
        return 2
    fi

    if ! require_command "$interpreter"; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" && [[ ! -f "$script_file" ]]; then
        printf 'Error: installer script file not found: %s\n' \
            "$script_file" >&2
        return 1
    fi

    log_info \
        "Executing staged installer script: installer=$LWBS_EXTERNAL_ID interpreter=$interpreter"

    run_command \
        "$interpreter" \
        "$script_file"
}

reset_external_installer_contract() {
    unset -f \
        external_id \
        external_name \
        external_description \
        external_method \
        external_state \
        external_validate_environment \
        external_repository_apply \
        external_package_apply \
        external_archive_apply \
        external_script_apply \
        2>/dev/null || true

    LWBS_EXTERNAL_ID=""
    LWBS_EXTERNAL_NAME=""
    LWBS_EXTERNAL_DESCRIPTION=""
    LWBS_EXTERNAL_METHOD=""
    LWBS_EXTERNAL_PATH=""
    LWBS_EXTERNAL_STAGE_DIR=""
}