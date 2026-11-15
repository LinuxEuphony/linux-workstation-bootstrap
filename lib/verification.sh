#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Post-execution verification and result tracking.
#
# This file:
# 1. Records final statuses for planned bootstrap actions.
# 2. Distinguishes successful, skipped, failed, and unverifiable actions.
# 3. Provides a concise final execution summary.
# 4. Records verification results in the session log.
# 5. Updates recovery state after successfully verified actions.
# 6. Keeps result tracking separate from installation implementation.

declare -a LWBS_RESULT_KEYS=()

declare -A LWBS_RESULT_TYPE=()
declare -A LWBS_RESULT_MODULE=()
declare -A LWBS_RESULT_TARGET=()
declare -A LWBS_RESULT_STATUS=()
declare -A LWBS_RESULT_DETAIL=()

LWBS_RESULT_SUCCESSFUL_COUNT=0
LWBS_RESULT_SKIPPED_COUNT=0
LWBS_RESULT_FAILED_COUNT=0
LWBS_RESULT_UNVERIFIABLE_COUNT=0

reset_execution_results() {
    LWBS_RESULT_KEYS=()

    LWBS_RESULT_TYPE=()
    LWBS_RESULT_MODULE=()
    LWBS_RESULT_TARGET=()
    LWBS_RESULT_STATUS=()
    LWBS_RESULT_DETAIL=()

    LWBS_RESULT_SUCCESSFUL_COUNT=0
    LWBS_RESULT_SKIPPED_COUNT=0
    LWBS_RESULT_FAILED_COUNT=0
    LWBS_RESULT_UNVERIFIABLE_COUNT=0
}

record_execution_result() {
    local key="${1:-}"
    local type="${2:-}"
    local module_id="${3:-}"
    local target="${4:-}"
    local status="${5:-}"
    local detail="${6:-}"

    if [[ -z "$key" ||
        -z "$type" ||
        -z "$module_id" ||
        -z "$target" ||
        -z "$status" ]]; then

        printf 'Error: incomplete execution result.\n' >&2
        return 2
    fi

    case "$status" in
        successful | skipped | failed | unverifiable) ;;
        *)
            printf 'Error: invalid execution result status: %s\n' \
                "$status" >&2
            return 2
            ;;
    esac

    if [[ -n "${LWBS_RESULT_STATUS[$key]+defined}" ]]; then
        printf 'Error: execution result already recorded: %s\n' \
            "$key" >&2
        return 1
    fi

    LWBS_RESULT_KEYS+=("$key")

    LWBS_RESULT_TYPE["$key"]="$type"
    LWBS_RESULT_MODULE["$key"]="$module_id"
    LWBS_RESULT_TARGET["$key"]="$target"
    LWBS_RESULT_STATUS["$key"]="$status"
    LWBS_RESULT_DETAIL["$key"]="$detail"

    case "$status" in
        successful)
            ((LWBS_RESULT_SUCCESSFUL_COUNT += 1))
            ;;

        skipped)
            ((LWBS_RESULT_SKIPPED_COUNT += 1))
            ;;

        failed)
            ((LWBS_RESULT_FAILED_COUNT += 1))
            ;;

        unverifiable)
            ((LWBS_RESULT_UNVERIFIABLE_COUNT += 1))
            ;;
    esac

    log_info \
        "Execution result: type=$type module=$module_id target=$target status=$status detail=${detail:-none}"

    if [[ "$status" == "successful" ]] &&
        declare -F recovery_record_successful_action >/dev/null 2>&1; then

        if recovery_record_successful_action \
            "$type" \
            "$module_id" \
            "$target"; then
            :
        else
            log_warning \
                "Execution succeeded but recovery checkpoint could not be updated: type=$type module=$module_id target=$target"
        fi
    fi

    return 0
}

package_result_key() {
    local module_id="${1:-}"
    local package="${2:-}"

    printf 'package::%s::%s\n' \
        "$module_id" \
        "$package"
}

external_result_key() {
    local module_id="${1:-}"
    local installer_id="${2:-}"

    printf 'external::%s::%s\n' \
        "$module_id" \
        "$installer_id"
}

module_result_key() {
    local module_id="${1:-}"

    printf 'module::%s\n' "$module_id"
}

show_execution_summary() {
    local key
    local status
    local type
    local target
    local module_id
    local detail

    printf '\nExecution summary\n\n'

    printf '  Successful   : %d\n' \
        "$LWBS_RESULT_SUCCESSFUL_COUNT"

    printf '  Skipped      : %d\n' \
        "$LWBS_RESULT_SKIPPED_COUNT"

    printf '  Failed       : %d\n' \
        "$LWBS_RESULT_FAILED_COUNT"

    printf '  Unverifiable : %d\n' \
        "$LWBS_RESULT_UNVERIFIABLE_COUNT"

    printf '\n'

    if ((${#LWBS_RESULT_KEYS[@]} == 0)); then
        printf '  No execution actions were recorded.\n\n'
        return 0
    fi

    for key in "${LWBS_RESULT_KEYS[@]}"; do
        status="${LWBS_RESULT_STATUS[$key]}"
        type="${LWBS_RESULT_TYPE[$key]}"
        target="${LWBS_RESULT_TARGET[$key]}"
        module_id="${LWBS_RESULT_MODULE[$key]}"
        detail="${LWBS_RESULT_DETAIL[$key]}"

        printf '  [%s] %s: %s (module: %s)' \
            "$status" \
            "$type" \
            "$target" \
            "$module_id"

        if [[ -n "$detail" ]]; then
            printf ' - %s' "$detail"
        fi

        printf '\n'
    done

    printf '\n'
}

execution_results_are_successful() {
    ((LWBS_RESULT_FAILED_COUNT == 0))
}
