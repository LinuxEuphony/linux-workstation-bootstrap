#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# External artifact integrity verification.
#
# Supported declarations:
#
#   <artifact-id>|sha256|<expected-sha256>
#
#   <artifact-id>|signature|<trusted-keyring>|<fingerprint>
#
# Signature verification uses an explicitly trusted local GPG keyring.
#
# shellcheck disable=SC2178

declare -a LWBS_EXTERNAL_INTEGRITY_IDS=()

declare -A LWBS_EXTERNAL_INTEGRITY_METHODS=()
declare -A LWBS_EXTERNAL_INTEGRITY_SHA256=()
declare -A LWBS_EXTERNAL_INTEGRITY_KEYRINGS=()
declare -A LWBS_EXTERNAL_INTEGRITY_FINGERPRINTS=()

declare -A LWBS_EXTERNAL_DOWNLOADED_PATHS=()
declare -A LWBS_EXTERNAL_VERIFIED_PATHS=()

reset_external_integrity_state() {
    LWBS_EXTERNAL_INTEGRITY_IDS=()

    LWBS_EXTERNAL_INTEGRITY_METHODS=()
    LWBS_EXTERNAL_INTEGRITY_SHA256=()
    LWBS_EXTERNAL_INTEGRITY_KEYRINGS=()
    LWBS_EXTERNAL_INTEGRITY_FINGERPRINTS=()

    LWBS_EXTERNAL_DOWNLOADED_PATHS=()
    LWBS_EXTERNAL_VERIFIED_PATHS=()
}

integrity_parse_requirement() {
    local requirement="${1:-}"
    local artifact_name="${2:-}"
    local method_name="${3:-}"
    local value_one_name="${4:-}"
    local value_two_name="${5:-}"

    local parsed_artifact
    local parsed_method
    local parsed_value_one
    local parsed_value_two
    local extra

    if [[ -z "$requirement" ||
        -z "$artifact_name" ||
        -z "$method_name" ||
        -z "$value_one_name" ||
        -z "$value_two_name" ]]; then

        return 2
    fi

    IFS='|' read -r \
        parsed_artifact \
        parsed_method \
        parsed_value_one \
        parsed_value_two \
        extra <<<"$requirement"

    if [[ -n "$extra" ||
        ! "$parsed_artifact" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then

        return 1
    fi

    case "$parsed_method" in
        sha256)
            if [[ ! "$parsed_value_one" =~ ^[A-Fa-f0-9]{64}$ ||
                -n "$parsed_value_two" ]]; then

                return 1
            fi

            parsed_value_one="${parsed_value_one,,}"
            ;;

        signature)
            if [[ "$parsed_value_one" != /* ||
                ! -r "$parsed_value_one" ||
                ! "$parsed_value_two" =~ ^([A-Fa-f0-9]{40}|[A-Fa-f0-9]{64})$ ]]; then

                return 1
            fi

            parsed_value_two="${parsed_value_two^^}"
            ;;

        *)
            return 1
            ;;
    esac

    local -n artifact_ref="$artifact_name"
    local -n method_ref="$method_name"
    local -n value_one_ref="$value_one_name"
    local -n value_two_ref="$value_two_name"

    artifact_ref="$parsed_artifact"
    method_ref="$parsed_method"
    value_one_ref="$parsed_value_one"
    value_two_ref="$parsed_value_two"

    return 0
}

load_external_integrity_requirements() {
    local requirement_output
    local requirement
    local artifact_id
    local method
    local value_one
    local value_two

    local -A seen_artifacts=()

    reset_external_integrity_state

    if ! declare -F external_integrity_requirements >/dev/null 2>&1; then
        return 0
    fi

    if requirement_output="$(external_integrity_requirements)"; then
        :
    else
        printf 'Error: unable to read external integrity requirements.\n' >&2
        return 1
    fi

    while IFS= read -r requirement; do
        [[ -z "$requirement" ]] && continue

        if ! integrity_parse_requirement \
            "$requirement" \
            artifact_id \
            method \
            value_one \
            value_two; then

            printf 'Error: invalid external integrity requirement.\n' >&2
            return 1
        fi

        if [[ -n "${seen_artifacts[$artifact_id]+defined}" ]]; then
            printf 'Error: duplicate external integrity artifact ID: %s\n' \
                "$artifact_id" >&2

            return 1
        fi

        seen_artifacts["$artifact_id"]=1

        LWBS_EXTERNAL_INTEGRITY_IDS+=("$artifact_id")
        LWBS_EXTERNAL_INTEGRITY_METHODS["$artifact_id"]="$method"

        case "$method" in
            sha256)
                LWBS_EXTERNAL_INTEGRITY_SHA256["$artifact_id"]="$value_one"
                ;;

            signature)
                LWBS_EXTERNAL_INTEGRITY_KEYRINGS["$artifact_id"]="$value_one"
                LWBS_EXTERNAL_INTEGRITY_FINGERPRINTS["$artifact_id"]="$value_two"
                ;;
        esac
    done <<<"$requirement_output"

    return 0
}

integrity_has_requirement() {
    local artifact_id="${1:-}"

    [[ -n "${LWBS_EXTERNAL_INTEGRITY_METHODS[$artifact_id]+defined}" ]]
}

integrity_verify_sha256() {
    local artifact_path="${1:-}"
    local expected_sha256="${2:-}"
    local checksum_output
    local actual_sha256

    if [[ ! -f "$artifact_path" ||
        ! "$expected_sha256" =~ ^[a-f0-9]{64}$ ]]; then

        return 2
    fi

    if ! command_exists sha256sum; then
        printf 'Error: SHA-256 verification requires sha256sum.\n' >&2
        return 1
    fi

    if checksum_output="$(sha256sum -- "$artifact_path")"; then
        :
    else
        return 1
    fi

    actual_sha256="${checksum_output%% *}"
    actual_sha256="${actual_sha256,,}"

    [[ "$actual_sha256" == "$expected_sha256" ]]
}

integrity_verify_signature() {
    local artifact_path="${1:-}"
    local signature_path="${2:-}"
    local keyring_path="${3:-}"
    local expected_fingerprint="${4:-}"
    local status_output
    local status_line
    local actual_fingerprint=""

    if [[ ! -f "$artifact_path" ||
        ! -f "$signature_path" ||
        ! -r "$keyring_path" ]]; then

        return 2
    fi

    if ! command_exists gpg; then
        printf 'Error: signature verification requires gpg.\n' >&2
        return 1
    fi

    if status_output="$(
        gpg \
            --batch \
            --no-default-keyring \
            --keyring "$keyring_path" \
            --status-fd 1 \
            --verify "$signature_path" "$artifact_path" \
            2>/dev/null
    )"; then
        :
    else
        return 1
    fi

    while IFS= read -r status_line; do
        if [[ "$status_line" != "[GNUPG:] VALIDSIG "* ]]; then
            continue
        fi

        status_line="${status_line#"[GNUPG:] VALIDSIG "}"
        actual_fingerprint="${status_line%% *}"
        actual_fingerprint="${actual_fingerprint^^}"

        break
    done <<<"$status_output"

    [[ -n "$actual_fingerprint" &&
        "$actual_fingerprint" == "${expected_fingerprint^^}" ]]
}

integrity_mark_downloaded() {
    local artifact_id="${1:-}"
    local artifact_path="${2:-}"

    LWBS_EXTERNAL_DOWNLOADED_PATHS["$artifact_path"]="$artifact_id"
}

integrity_mark_planned() {
    local artifact_id="${1:-}"
    local artifact_path="${2:-}"

    integrity_mark_downloaded \
        "$artifact_id" \
        "$artifact_path"

    LWBS_EXTERNAL_VERIFIED_PATHS["$artifact_path"]="planned:$artifact_id"
}

integrity_mark_verified() {
    local artifact_id="${1:-}"
    local artifact_path="${2:-}"

    integrity_mark_downloaded \
        "$artifact_id" \
        "$artifact_path"

    LWBS_EXTERNAL_VERIFIED_PATHS["$artifact_path"]="verified:$artifact_id"
}

integrity_verify_artifact() {
    local artifact_id="${1:-}"
    local artifact_path="${2:-}"
    local signature_path="${3:-}"
    local method

    if ! integrity_has_requirement "$artifact_id"; then
        printf 'Error: verification metadata is unavailable for external artifact: %s\n' \
            "$artifact_id" >&2

        return 1
    fi

    method="${LWBS_EXTERNAL_INTEGRITY_METHODS[$artifact_id]}"

    case "$method" in
        sha256)
            if ! integrity_verify_sha256 \
                "$artifact_path" \
                "${LWBS_EXTERNAL_INTEGRITY_SHA256[$artifact_id]}"; then

                printf 'Error: SHA-256 verification failed for external artifact: %s\n' \
                    "$artifact_id" >&2

                return 1
            fi
            ;;

        signature)
            if [[ -z "$signature_path" ]]; then
                printf 'Error: signature file is required for external artifact: %s\n' \
                    "$artifact_id" >&2

                return 1
            fi

            if ! integrity_verify_signature \
                "$artifact_path" \
                "$signature_path" \
                "${LWBS_EXTERNAL_INTEGRITY_KEYRINGS[$artifact_id]}" \
                "${LWBS_EXTERNAL_INTEGRITY_FINGERPRINTS[$artifact_id]}"; then

                printf 'Error: trusted signature verification failed for external artifact: %s\n' \
                    "$artifact_id" >&2

                return 1
            fi
            ;;
    esac

    integrity_mark_verified \
        "$artifact_id" \
        "$artifact_path"

    log_info \
        "External artifact verification passed: installer=${LWBS_EXTERNAL_ID:-unknown} artifact=$artifact_id method=$method"

    return 0
}

integrity_quarantine_file() {
    local artifact_path="${1:-}"
    local quarantine_directory
    local quarantine_path

    if [[ -z "$artifact_path" ||
        ! -e "$artifact_path" ]]; then

        return 0
    fi

    if [[ -z "${LWBS_EXTERNAL_STAGE_DIR:-}" ]]; then
        rm -f -- "$artifact_path"
        return $?
    fi

    quarantine_directory="$LWBS_EXTERNAL_STAGE_DIR/quarantine"

    if ! mkdir -p -- "$quarantine_directory"; then
        rm -f -- "$artifact_path"
        return $?
    fi

    quarantine_path="$quarantine_directory/$(basename -- "$artifact_path").failed"

    rm -f -- "$quarantine_path"

    mv -- "$artifact_path" "$quarantine_path"
}

integrity_require_verified_if_downloaded() {
    local artifact_path="${1:-}"
    local verification_state

    if [[ -z "${LWBS_EXTERNAL_DOWNLOADED_PATHS[$artifact_path]+defined}" ]]; then
        return 0
    fi

    verification_state="${LWBS_EXTERNAL_VERIFIED_PATHS[$artifact_path]:-}"

    case "$verification_state" in
        verified:* | planned:*)
            return 0
            ;;

        *)
            printf 'Error: external artifact has not passed required integrity verification.\n' \
                >&2

            return 1
            ;;
    esac
}
