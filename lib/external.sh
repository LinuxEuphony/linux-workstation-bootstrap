#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# External software installation framework.

LWBS_EXTERNAL_ID=""
LWBS_EXTERNAL_NAME=""
LWBS_EXTERNAL_DESCRIPTION=""
LWBS_EXTERNAL_METHOD=""
LWBS_EXTERNAL_PATH=""
LWBS_EXTERNAL_STAGE_DIR=""

declare -a LWBS_EXTERNAL_RESTART_REQUIREMENTS=()

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
    local restart_output
    local restart_requirement
    local restart_type
    local restart_target
    local restart_reason

    local -A seen_restart_requirements=()

    if [[ -z "$requested_installer" ]]; then
        printf 'Error: no external installer was provided.\n' >&2
        return 2
    fi

    if [[ ! "$requested_installer" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid external installer ID: %s\n' \
            "$requested_installer" >&2

        return 2
    fi

    installer_directory="${LWBS_EXTERNAL_INSTALLERS_DIR_OVERRIDE:-$LWBS_ROOT/installers}"
    installer_path="$installer_directory/$requested_installer.sh"

    if [[ ! -r "$installer_path" ]]; then
        printf 'Error: external installer not found: %s\n' \
            "$installer_path" >&2

        return 1
    fi

    reset_external_installer_contract

    log_info "Loading external installer: $requested_installer"

    # shellcheck disable=SC1090
    if ! source "$installer_path"; then
        printf 'Error: failed to load external installer: %s\n' \
            "$requested_installer" >&2

        reset_external_installer_contract
        return 1
    fi

    if ! validate_external_installer_contract; then
        reset_external_installer_contract
        return 1
    fi

    LWBS_EXTERNAL_ID="$(external_id)"
    LWBS_EXTERNAL_NAME="$(external_name)"
    LWBS_EXTERNAL_DESCRIPTION="$(external_description)"
    LWBS_EXTERNAL_METHOD="$(external_method)"

    if [[ -z "$LWBS_EXTERNAL_ID" ||
        "$LWBS_EXTERNAL_ID" != "$requested_installer" ||
        -z "$LWBS_EXTERNAL_NAME" ||
        -z "$LWBS_EXTERNAL_DESCRIPTION" ]]; then

        printf 'Error: invalid external installer metadata: %s\n' \
            "$requested_installer" >&2

        reset_external_installer_contract
        return 1
    fi

    if ! is_supported_external_method "$LWBS_EXTERNAL_METHOD"; then
        printf 'Error: unsupported external installation method "%s" for installer "%s".\n' \
            "$LWBS_EXTERNAL_METHOD" \
            "$requested_installer" >&2

        reset_external_installer_contract
        return 1
    fi

    if ! validate_external_method_contract "$LWBS_EXTERNAL_METHOD"; then
        reset_external_installer_contract
        return 1
    fi

    if ! load_external_integrity_requirements; then
        reset_external_installer_contract
        return 1
    fi

    LWBS_EXTERNAL_RESTART_REQUIREMENTS=()

    if declare -F external_restart_requirements >/dev/null 2>&1; then
        if restart_output="$(external_restart_requirements)"; then
            :
        else
            reset_external_installer_contract
            return 1
        fi

        while IFS= read -r restart_requirement; do
            [[ -z "$restart_requirement" ]] && continue

            if ! parse_restart_requirement \
                "$restart_requirement" \
                restart_type \
                restart_target \
                restart_reason; then

                reset_external_installer_contract
                return 1
            fi

            restart_requirement="$restart_type|$restart_target|$restart_reason"

            if [[ -n "${seen_restart_requirements[$restart_requirement]+defined}" ]]; then
                continue
            fi

            seen_restart_requirements["$restart_requirement"]=1
            LWBS_EXTERNAL_RESTART_REQUIREMENTS+=("$restart_requirement")
        done <<<"$restart_output"
    fi

    LWBS_EXTERNAL_PATH="$installer_path"

    log_info \
        "External installer loaded: id=$LWBS_EXTERNAL_ID method=$LWBS_EXTERNAL_METHOD integrity_requirements=${#LWBS_EXTERNAL_INTEGRITY_IDS[@]} restart_requirements=${#LWBS_EXTERNAL_RESTART_REQUIREMENTS[@]}"

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

query_external_installation_state() {
    local installation_state
    local exit_code

    if [[ -z "$LWBS_EXTERNAL_ID" ]]; then
        return 2
    fi

    if installation_state="$(external_state)"; then
        :
    else
        exit_code=$?

        printf 'Error: unable to determine external software state: %s\n' \
            "$LWBS_EXTERNAL_ID" >&2

        return "$exit_code"
    fi

    case "$installation_state" in
        installed | absent)
            printf '%s\n' "$installation_state"
            ;;

        *)
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
        return 2
    fi

    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ]]; then
        return 1
    fi

    printf '\nExternal software: %s\n' "$LWBS_EXTERNAL_NAME"
    printf '  ID          : %s\n' "$LWBS_EXTERNAL_ID"
    printf '  Description : %s\n' "$LWBS_EXTERNAL_DESCRIPTION"
    printf '  Method      : %s\n' "$LWBS_EXTERNAL_METHOD"

    if installation_state="$(query_external_installation_state)"; then
        :
    else
        state_exit_code=$?
        return "$state_exit_code"
    fi

    if [[ "$installation_state" == "installed" ]]; then
        printf '  Status      : already installed\n'
        printf '  Action      : skip\n'
        return 0
    fi

    printf '  Status      : not installed\n'

    if declare -F external_validate_environment >/dev/null 2>&1; then
        if external_validate_environment; then
            :
        else
            validation_exit_code=$?
            return "$validation_exit_code"
        fi
    fi

    if ! prepare_external_staging; then
        return 1
    fi

    apply_function="external_${LWBS_EXTERNAL_METHOD}_apply"

    if "$apply_function"; then
        apply_exit_code=0
    else
        apply_exit_code=$?
    fi

    if cleanup_external_staging; then
        cleanup_exit_code=0
    else
        cleanup_exit_code=$?
    fi

    if ((apply_exit_code != 0)); then
        return "$apply_exit_code"
    fi

    if ((cleanup_exit_code != 0)); then
        return "$cleanup_exit_code"
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
        return 0
    fi

    if [[ ! -d "$temp_root" || ! -w "$temp_root" ]]; then
        return 1
    fi

    if ! LWBS_EXTERNAL_STAGE_DIR="$(
        mktemp -d "$temp_root/${LWBS_APP_SLUG}-external.XXXXXX"
    )"; then
        return 1
    fi

    chmod 700 -- "$LWBS_EXTERNAL_STAGE_DIR"

    return 0
}

cleanup_external_staging() {
    local stage_directory="$LWBS_EXTERNAL_STAGE_DIR"

    LWBS_EXTERNAL_STAGE_DIR=""

    if [[ -z "$stage_directory" ||
        "$LWBS_DRY_RUN" == "true" ]]; then

        return 0
    fi

    if [[ ! -d "$stage_directory" ]]; then
        return 0
    fi

    run_command rm -rf -- "$stage_directory"
}

external_stage_path() {
    local filename="${1:-}"

    if [[ -z "$LWBS_EXTERNAL_STAGE_DIR" ]]; then
        return 1
    fi

    if [[ -z "$filename" ||
        ! "$filename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then

        return 2
    fi

    printf '%s/%s\n' \
        "$LWBS_EXTERNAL_STAGE_DIR" \
        "$filename"
}

external_validate_https_url() {
    local url="${1:-}"

    [[ "$url" =~ ^https://[^[:space:]]+$ ]]
}

external_download_raw() {
    local url="${1:-}"
    local destination="${2:-}"

    if ! external_validate_https_url "$url"; then
        printf 'Error: external download URL must use HTTPS.\n' >&2
        return 1
    fi

    if [[ "$destination" != /* ]]; then
        return 2
    fi

    if ! require_command curl; then
        return 1
    fi

    run_command \
        curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --output "$destination" \
        "$url"
}

external_download() {
    local artifact_id="${1:-}"
    local url="${2:-}"
    local destination="${3:-}"
    local signature_url="${4:-}"
    local method
    local signature_path=""

    if [[ -z "$artifact_id" ||
        -z "$url" ||
        -z "$destination" ]]; then

        return 2
    fi

    if ! integrity_has_requirement "$artifact_id"; then
        printf 'Error: external download requires verification metadata for artifact: %s\n' \
            "$artifact_id" >&2

        return 1
    fi

    if ! external_validate_https_url "$url"; then
        printf 'Error: external download URL must use HTTPS.\n' >&2
        return 1
    fi

    method="${LWBS_EXTERNAL_INTEGRITY_METHODS[$artifact_id]}"

    if [[ "$method" == "signature" ]]; then
        if [[ -z "$signature_url" ]] ||
            ! external_validate_https_url "$signature_url"; then

            printf 'Error: signed external artifact requires a valid HTTPS signature URL.\n' \
                >&2

            return 1
        fi

        signature_path="${destination}.sig"
    elif [[ -n "$signature_url" ]]; then
        printf 'Error: checksum-verified artifact does not accept a signature URL.\n' \
            >&2

        return 2
    fi

    integrity_mark_downloaded \
        "$artifact_id" \
        "$destination"

    if "$LWBS_DRY_RUN"; then
        integrity_mark_planned \
            "$artifact_id" \
            "$destination"

        log_info \
            "Dry-run external artifact verification planned: installer=$LWBS_EXTERNAL_ID artifact=$artifact_id method=$method"

        return 0
    fi

    if ! external_download_raw \
        "$url" \
        "$destination"; then

        return 1
    fi

    if [[ "$method" == "signature" ]]; then
        if ! external_download_raw \
            "$signature_url" \
            "$signature_path"; then

            integrity_quarantine_file "$destination"
            return 1
        fi
    fi

    if integrity_verify_artifact \
        "$artifact_id" \
        "$destination" \
        "$signature_path"; then

        return 0
    fi

    integrity_quarantine_file "$destination"

    if [[ -n "$signature_path" ]]; then
        integrity_quarantine_file "$signature_path"
    fi

    return 1
}

external_install_local_package() {
    local package_file="${1:-}"

    if [[ -z "$package_file" ||
        "$package_file" != /* ]]; then

        return 2
    fi

    if ! integrity_require_verified_if_downloaded "$package_file"; then
        return 1
    fi

    if ! declare -F distro_install_local_package >/dev/null 2>&1; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" &&
        [[ ! -f "$package_file" ]]; then

        return 1
    fi

    distro_install_local_package "$package_file"
}

external_install_system_file() {
    local source_file="${1:-}"
    local destination="${2:-}"
    local mode="${3:-0644}"

    if [[ -z "$source_file" ||
        -z "$destination" ||
        "$source_file" != /* ||
        "$destination" != /* ]]; then

        return 2
    fi

    if ! integrity_require_verified_if_downloaded "$source_file"; then
        return 1
    fi

    if [[ ! "$mode" =~ ^0?[0-7]{3,4}$ ]]; then
        return 2
    fi

    if ! "$LWBS_DRY_RUN" &&
        [[ ! -f "$source_file" ]]; then

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

    if [[ -z "$archive_file" ||
        -z "$destination" ||
        "$archive_file" != /* ||
        "$destination" != /* ]]; then

        return 2
    fi

    if ! integrity_require_verified_if_downloaded "$archive_file"; then
        return 1
    fi

    if ! require_command tar; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" &&
        [[ ! -f "$archive_file" ]]; then

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

    if [[ -z "$archive_file" ||
        -z "$destination" ||
        "$archive_file" != /* ||
        "$destination" != /* ]]; then

        return 2
    fi

    if ! integrity_require_verified_if_downloaded "$archive_file"; then
        return 1
    fi

    if ! require_command unzip; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" &&
        [[ ! -f "$archive_file" ]]; then

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

    if [[ -z "$interpreter" ||
        -z "$script_file" ||
        "$script_file" != /* ]]; then

        return 2
    fi

    if ! integrity_require_verified_if_downloaded "$script_file"; then
        return 1
    fi

    if ! require_command "$interpreter"; then
        return 1
    fi

    if ! "$LWBS_DRY_RUN" &&
        [[ ! -f "$script_file" ]]; then

        return 1
    fi

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
        external_preflight_requirements \
        external_integrity_requirements \
        external_restart_requirements \
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
    LWBS_EXTERNAL_RESTART_REQUIREMENTS=()

    reset_external_integrity_state
}
