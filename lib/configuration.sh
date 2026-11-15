#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Managed workstation configuration framework.
#
# Modules may declare complete managed files or managed blocks. The framework
# inspects desired state during planning, avoids unnecessary rewrites, creates
# optional backups, applies replacements atomically where practical, preserves
# existing ownership, enforces declared permissions, and records results
# without logging configuration contents.
#
# Declaration format:
#
#   id|kind|scope|destination|source|mode|backup
#
# kind:
#   file  - the complete destination file is managed
#   block - one marked block inside a line-oriented configuration file is managed
#
# scope:
#   user   - mutate as the current user
#   system - mutate through the shared privileged execution layer
#
# backup:
#   backup
#   no-backup
#
# Block mode uses # comments as ownership markers and is intended only for
# line-oriented configuration formats that accept # comments.

LWBS_PLAN_CONFIGURATION_ACTION_COUNT=0

declare -A LWBS_PLAN_MODULE_CONFIGURATIONS=()
declare -A LWBS_PLAN_CONFIGURATION_KIND=()
declare -A LWBS_PLAN_CONFIGURATION_SCOPE=()
declare -A LWBS_PLAN_CONFIGURATION_DESTINATION=()
declare -A LWBS_PLAN_CONFIGURATION_SOURCE=()
declare -A LWBS_PLAN_CONFIGURATION_MODE=()
declare -A LWBS_PLAN_CONFIGURATION_BACKUP=()
declare -A LWBS_PLAN_CONFIGURATION_ACTION=()
declare -A LWBS_PLAN_CONFIGURATION_DESTINATION_OWNER=()

configuration_plan_key() {
    printf '%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

configuration_result_key() {
    printf 'configuration::%s::%s\n' \
        "${1:-}" \
        "${2:-}"
}

normalize_configuration_mode() {
    local mode="${1:-}"

    if [[ ${#mode} -eq 4 && "$mode" == 0* ]]; then
        printf '%s\n' "${mode:1}"
    else
        printf '%s\n' "$mode"
    fi
}

parse_configuration_requirement() {
    local requirement="${1:-}"
    local id_name="${2:-}"
    local kind_name="${3:-}"
    local scope_name="${4:-}"
    local destination_name="${5:-}"
    local source_name="${6:-}"
    local mode_name="${7:-}"
    local backup_name="${8:-}"

    local parsed_id
    local parsed_kind
    local parsed_scope
    local parsed_destination
    local parsed_source
    local parsed_mode
    local parsed_backup
    local extra

    if [[ -z "$requirement" ||
        -z "$id_name" ||
        -z "$kind_name" ||
        -z "$scope_name" ||
        -z "$destination_name" ||
        -z "$source_name" ||
        -z "$mode_name" ||
        -z "$backup_name" ]]; then

        printf 'Error: incomplete managed configuration parser request.\n' >&2
        return 2
    fi

    IFS='|' read -r \
        parsed_id \
        parsed_kind \
        parsed_scope \
        parsed_destination \
        parsed_source \
        parsed_mode \
        parsed_backup \
        extra <<<"$requirement"

    if [[ -n "$extra" ]]; then
        printf 'Error: managed configuration declaration has too many fields.\n' \
            >&2
        return 1
    fi

    if [[ ! "$parsed_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        printf 'Error: invalid managed configuration ID: %s\n' \
            "$parsed_id" >&2
        return 1
    fi

    case "$parsed_kind" in
        file | block) ;;
        *)
            printf 'Error: invalid managed configuration kind for %s: %s\n' \
                "$parsed_id" \
                "$parsed_kind" >&2
            return 1
            ;;
    esac

    case "$parsed_scope" in
        user | system) ;;
        *)
            printf 'Error: invalid managed configuration scope for %s: %s\n' \
                "$parsed_id" \
                "$parsed_scope" >&2
            return 1
            ;;
    esac

    if [[ "$parsed_destination" != /* ]]; then
        printf 'Error: managed configuration destination must be absolute for %s.\n' \
            "$parsed_id" >&2
        return 1
    fi

    if [[ "$parsed_source" != /* ]]; then
        printf 'Error: managed configuration source must be absolute for %s.\n' \
            "$parsed_id" >&2
        return 1
    fi

    if [[ ! -f "$parsed_source" || ! -r "$parsed_source" ]]; then
        printf 'Error: managed configuration source is unavailable for %s: %s\n' \
            "$parsed_id" \
            "$parsed_source" >&2
        return 1
    fi

    if [[ ! "$parsed_mode" =~ ^[0-7]{3,4}$ ]]; then
        printf 'Error: invalid managed configuration mode for %s: %s\n' \
            "$parsed_id" \
            "$parsed_mode" >&2
        return 1
    fi

    case "$parsed_backup" in
        backup | no-backup) ;;
        *)
            printf 'Error: invalid managed configuration backup policy for %s: %s\n' \
                "$parsed_id" \
                "$parsed_backup" >&2
            return 1
            ;;
    esac

    local -n id_ref="$id_name"
    local -n kind_ref="$kind_name"
    local -n scope_ref="$scope_name"
    local -n destination_ref="$destination_name"
    local -n source_ref="$source_name"
    local -n mode_ref="$mode_name"
    local -n backup_ref="$backup_name"

    id_ref="$parsed_id"
    kind_ref="$parsed_kind"
    scope_ref="$parsed_scope"
    destination_ref="$parsed_destination"
    source_ref="$parsed_source"
    mode_ref="$parsed_mode"
    backup_ref="$parsed_backup"

    return 0
}

configuration_render_block() {
    local configuration_id="${1:-}"
    local destination="${2:-}"
    local source="${3:-}"
    local output="${4:-}"

    local begin_marker
    local end_marker
    local line
    local found_begin=false
    local inside_block=false
    local replaced=false
    local source_last_byte_lines

    begin_marker="# >>> linux-workstation-bootstrap:${configuration_id} >>>"
    end_marker="# <<< linux-workstation-bootstrap:${configuration_id} <<<"

    : >"$output"

    if [[ -e "$destination" ]]; then
        if [[ ! -f "$destination" || ! -r "$destination" ]]; then
            printf 'Error: managed block destination is not a readable regular file: %s\n' \
                "$destination" >&2
            return 1
        fi

        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "$begin_marker" ]]; then
                if "$found_begin"; then
                    printf 'Error: duplicate managed block marker in %s for %s.\n' \
                        "$destination" \
                        "$configuration_id" >&2
                    return 1
                fi

                found_begin=true
                inside_block=true
                replaced=true

                printf '%s\n' "$begin_marker" >>"$output"
                cat -- "$source" >>"$output"

                if [[ -s "$source" ]]; then
                    source_last_byte_lines="$(
                        tail -c 1 -- "$source" |
                            wc -l
                    )"

                    if ((source_last_byte_lines == 0)); then
                        printf '\n' >>"$output"
                    fi
                fi

                printf '%s\n' "$end_marker" >>"$output"
                continue
            fi

            if "$inside_block"; then
                if [[ "$line" == "$end_marker" ]]; then
                    inside_block=false
                fi

                continue
            fi

            if [[ "$line" == "$end_marker" ]]; then
                printf 'Error: unmatched managed block end marker in %s for %s.\n' \
                    "$destination" \
                    "$configuration_id" >&2
                return 1
            fi

            printf '%s\n' "$line" >>"$output"
        done <"$destination"

        if "$inside_block"; then
            printf 'Error: unterminated managed block in %s for %s.\n' \
                "$destination" \
                "$configuration_id" >&2
            return 1
        fi
    fi

    if ! "$replaced"; then
        if [[ -s "$output" ]]; then
            printf '\n' >>"$output"
        fi

        printf '%s\n' "$begin_marker" >>"$output"
        cat -- "$source" >>"$output"

        if [[ -s "$source" ]]; then
            source_last_byte_lines="$(
                tail -c 1 -- "$source" |
                    wc -l
            )"

            if ((source_last_byte_lines == 0)); then
                printf '\n' >>"$output"
            fi
        fi

        printf '%s\n' "$end_marker" >>"$output"
    fi

    return 0
}

configuration_prepare_desired_file() {
    local kind="${1:-}"
    local configuration_id="${2:-}"
    local destination="${3:-}"
    local source="${4:-}"
    local output_name="${5:-}"

    local temporary_file
    local exit_code

    if temporary_file="$(
        mktemp \
            "${TMPDIR:-/tmp}/${LWBS_APP_SLUG}-configuration.XXXXXX"
    )"; then
        :
    else
        return $?
    fi

    chmod 600 -- "$temporary_file"

    case "$kind" in
        file)
            if cp -- "$source" "$temporary_file"; then
                :
            else
                exit_code=$?
                rm -f -- "$temporary_file"
                return "$exit_code"
            fi
            ;;

        block)
            if configuration_render_block \
                "$configuration_id" \
                "$destination" \
                "$source" \
                "$temporary_file"; then
                :
            else
                exit_code=$?
                rm -f -- "$temporary_file"
                return "$exit_code"
            fi
            ;;

        *)
            rm -f -- "$temporary_file"
            return 2
            ;;
    esac

    local -n output_ref="$output_name"
    output_ref="$temporary_file"

    return 0
}

configuration_state() {
    local kind="${1:-}"
    local configuration_id="${2:-}"
    local destination="${3:-}"
    local source="${4:-}"
    local mode="${5:-}"

    local desired_file
    local current_mode
    local expected_mode
    local exit_code
    local content_matches=false

    if configuration_prepare_desired_file \
        "$kind" \
        "$configuration_id" \
        "$destination" \
        "$source" \
        desired_file; then
        :
    else
        return $?
    fi

    if [[ ! -e "$destination" ]]; then
        rm -f -- "$desired_file"
        printf '%s\n' "create"
        return 0
    fi

    if [[ ! -f "$destination" || ! -r "$destination" ]]; then
        rm -f -- "$desired_file"

        printf 'Error: managed configuration destination is not a readable regular file: %s\n' \
            "$destination" >&2
        return 1
    fi

    if cmp -s -- "$desired_file" "$destination"; then
        content_matches=true
    else
        exit_code=$?

        if ((exit_code > 1)); then
            rm -f -- "$desired_file"
            return "$exit_code"
        fi
    fi

    rm -f -- "$desired_file"

    current_mode="$(stat -c '%a' -- "$destination")"
    expected_mode="$(normalize_configuration_mode "$mode")"

    if "$content_matches" &&
        [[ "$current_mode" == "$expected_mode" ]]; then

        printf '%s\n' "skip"
        return 0
    fi

    printf '%s\n' "update"

    return 0
}

configuration_user_destination_is_writable() {
    local destination="${1:-}"
    local candidate
    local owner_uid

    if [[ -e "$destination" ]]; then
        if [[ ! -f "$destination" ]]; then
            return 1
        fi

        owner_uid="$(stat -c '%u' -- "$destination")"

        [[ "$owner_uid" == "$EUID" && -w "$destination" ]]
        return $?
    fi

    candidate="$(dirname -- "$destination")"

    while [[ ! -e "$candidate" ]]; do
        if [[ "$candidate" == "/" ]]; then
            break
        fi

        candidate="$(dirname -- "$candidate")"
    done

    [[ -d "$candidate" && -w "$candidate" ]]
}

plan_module_configurations() {
    local module_id="${1:-}"
    local requirement
    local configuration_id
    local kind
    local scope
    local destination
    local source
    local mode
    local backup
    local configuration_key
    local current_state
    local exit_code
    local existing_owner

    local -A seen_configuration_ids=()

    for requirement in "${LWBS_MODULE_CONFIGURATIONS[@]}"; do
        if parse_configuration_requirement \
            "$requirement" \
            configuration_id \
            kind \
            scope \
            destination \
            source \
            mode \
            backup; then
            :
        else
            return $?
        fi

        if [[ -n "${seen_configuration_ids[$configuration_id]+defined}" ]]; then
            printf 'Error: duplicate managed configuration ID in module %s: %s\n' \
                "$module_id" \
                "$configuration_id" >&2
            return 1
        fi

        seen_configuration_ids["$configuration_id"]=1

        existing_owner="${LWBS_PLAN_CONFIGURATION_DESTINATION_OWNER[$destination]:-}"

        if [[ -n "$existing_owner" ]]; then
            printf 'Error: managed configuration destination is declared more than once: %s\n' \
                "$destination" >&2
            return 1
        fi

        if [[ "$scope" == "user" ]] &&
            ! configuration_user_destination_is_writable "$destination"; then

            printf 'Error: user-scoped configuration destination is not writable: %s\n' \
                "$destination" >&2
            return 1
        fi

        configuration_key="$(
            configuration_plan_key \
                "$module_id" \
                "$configuration_id"
        )"

        if current_state="$(
            configuration_state \
                "$kind" \
                "$configuration_id" \
                "$destination" \
                "$source" \
                "$mode"
        )"; then
            :
        else
            exit_code=$?
            return "$exit_code"
        fi

        append_execution_plan_value \
            LWBS_PLAN_MODULE_CONFIGURATIONS \
            "$module_id" \
            "$configuration_id"

        LWBS_PLAN_CONFIGURATION_KIND["$configuration_key"]="$kind"
        LWBS_PLAN_CONFIGURATION_SCOPE["$configuration_key"]="$scope"
        LWBS_PLAN_CONFIGURATION_DESTINATION["$configuration_key"]="$destination"
        LWBS_PLAN_CONFIGURATION_SOURCE["$configuration_key"]="$source"
        LWBS_PLAN_CONFIGURATION_MODE["$configuration_key"]="$mode"
        LWBS_PLAN_CONFIGURATION_BACKUP["$configuration_key"]="$backup"
        LWBS_PLAN_CONFIGURATION_ACTION["$configuration_key"]="$current_state"

        LWBS_PLAN_CONFIGURATION_DESTINATION_OWNER["$destination"]="$configuration_key"

        if [[ "$current_state" == "skip" ]]; then
            ((LWBS_PLAN_SKIP_ACTION_COUNT += 1))
        else
            ((LWBS_PLAN_CONFIGURATION_ACTION_COUNT += 1))
        fi

        log_info \
            "Configuration plan: module=$module_id id=$configuration_id action=$current_state scope=$scope destination=$destination"
    done

    return 0
}

module_has_planned_configuration_changes() {
    local module_id="${1:-}"
    local configuration_id
    local configuration_key

    while IFS= read -r configuration_id; do
        [[ -z "$configuration_id" ]] && continue

        configuration_key="$(
            configuration_plan_key \
                "$module_id" \
                "$configuration_id"
        )"

        if [[ "${LWBS_PLAN_CONFIGURATION_ACTION[$configuration_key]:-skip}" != "skip" ]]; then
            return 0
        fi
    done <<<"${LWBS_PLAN_MODULE_CONFIGURATIONS[$module_id]:-}"

    return 1
}

configuration_plan_requires_privilege() {
    local module_id
    local configuration_id
    local configuration_key
    local action
    local scope

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        while IFS= read -r configuration_id; do
            [[ -z "$configuration_id" ]] && continue

            configuration_key="$(
                configuration_plan_key \
                    "$module_id" \
                    "$configuration_id"
            )"

            action="${LWBS_PLAN_CONFIGURATION_ACTION[$configuration_key]:-skip}"
            scope="${LWBS_PLAN_CONFIGURATION_SCOPE[$configuration_key]:-user}"

            if [[ "$action" != "skip" && "$scope" == "system" ]]; then
                return 0
            fi
        done <<<"${LWBS_PLAN_MODULE_CONFIGURATIONS[$module_id]:-}"
    done

    return 1
}

show_module_configuration_plan() {
    local module_id="${1:-}"
    local configuration_id
    local configuration_key
    local kind
    local scope
    local destination
    local action

    while IFS= read -r configuration_id; do
        [[ -z "$configuration_id" ]] && continue

        configuration_key="$(
            configuration_plan_key \
                "$module_id" \
                "$configuration_id"
        )"

        kind="${LWBS_PLAN_CONFIGURATION_KIND[$configuration_key]}"
        scope="${LWBS_PLAN_CONFIGURATION_SCOPE[$configuration_key]}"
        destination="${LWBS_PLAN_CONFIGURATION_DESTINATION[$configuration_key]}"
        action="${LWBS_PLAN_CONFIGURATION_ACTION[$configuration_key]}"

        printf '  Configuration: %s [%s, %s, %s -> %s]\n' \
            "$configuration_id" \
            "$kind" \
            "$scope" \
            "$action" \
            "$destination"
    done <<<"${LWBS_PLAN_MODULE_CONFIGURATIONS[$module_id]:-}"
}

configuration_create_backup() {
    local scope="${1:-}"
    local destination="${2:-}"
    local backup_path
    local exit_code

    printf -v backup_path \
        '%s.lwbs-backup.%(%Y%m%d-%H%M%S)T.%s' \
        "$destination" \
        -1 \
        "$$"

    case "$scope" in
        user)
            if run_command \
                cp \
                -p \
                -- "$destination" "$backup_path"; then
                return 0
            else
                exit_code=$?
                return "$exit_code"
            fi
            ;;

        system)
            if run_privileged_command \
                cp \
                -p \
                -- "$destination" "$backup_path"; then
                return 0
            else
                exit_code=$?
                return "$exit_code"
            fi
            ;;

        *)
            return 2
            ;;
    esac
}

configuration_cleanup_atomic_file() {
    local scope="${1:-}"
    local path="${2:-}"

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    case "$scope" in
        user)
            rm -f -- "$path"
            ;;

        system)
            run_privileged_command rm -f -- "$path"
            ;;

        *)
            return 2
            ;;
    esac
}

configuration_atomic_replace() {
    local scope="${1:-}"
    local destination="${2:-}"
    local desired_file="${3:-}"
    local mode="${4:-}"

    local parent
    local base
    local atomic_path
    local exit_code

    parent="$(dirname -- "$destination")"
    base="$(basename -- "$destination")"
    atomic_path="$parent/.${base}.lwbs-new.$$"

    case "$scope" in
        user)
            if [[ -e "$destination" ]]; then
                if [[ "$(stat -c '%u' -- "$destination")" != "$EUID" ]]; then
                    printf 'Error: user-scoped configuration is not owned by the current user: %s\n' \
                        "$destination" >&2
                    return 1
                fi
            fi

            if run_command mkdir -p -- "$parent"; then
                :
            else
                return $?
            fi

            if [[ -e "$destination" ]]; then
                if run_command cp -p -- "$destination" "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi

                if run_command \
                    cp \
                    --no-preserve=mode,ownership,timestamps \
                    -- "$desired_file" "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi

                if run_command chmod "$mode" -- "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi
            else
                if run_command \
                    install \
                    -m "$mode" \
                    -- "$desired_file" "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi
            fi

            if run_command mv -f -- "$atomic_path" "$destination"; then
                return 0
            else
                exit_code=$?
                configuration_cleanup_atomic_file \
                    "$scope" \
                    "$atomic_path" || true
                return "$exit_code"
            fi
            ;;

        system)
            if run_privileged_command mkdir -p -- "$parent"; then
                :
            else
                return $?
            fi

            if [[ -e "$destination" ]]; then
                if run_privileged_command \
                    cp \
                    -p \
                    -- "$destination" "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi

                if run_privileged_command \
                    cp \
                    --no-preserve=mode,ownership,timestamps \
                    -- "$desired_file" "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi

                if run_privileged_command \
                    chmod \
                    "$mode" \
                    -- "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi
            else
                if run_privileged_command \
                    install \
                    -m "$mode" \
                    -- "$desired_file" "$atomic_path"; then
                    :
                else
                    exit_code=$?
                    configuration_cleanup_atomic_file \
                        "$scope" \
                        "$atomic_path" || true
                    return "$exit_code"
                fi
            fi

            if run_privileged_command \
                mv \
                -f \
                -- "$atomic_path" "$destination"; then
                return 0
            else
                exit_code=$?
                configuration_cleanup_atomic_file \
                    "$scope" \
                    "$atomic_path" || true
                return "$exit_code"
            fi
            ;;

        *)
            return 2
            ;;
    esac
}

execute_planned_configuration_actions() {
    local module_id="${1:-}"
    local configuration_id
    local configuration_key
    local result_key
    local kind
    local scope
    local destination
    local source
    local mode
    local backup
    local planned_action
    local current_state
    local desired_file
    local exit_code

    while IFS= read -r configuration_id; do
        [[ -z "$configuration_id" ]] && continue

        configuration_key="$(
            configuration_plan_key \
                "$module_id" \
                "$configuration_id"
        )"

        result_key="$(
            configuration_result_key \
                "$module_id" \
                "$configuration_id"
        )"

        kind="${LWBS_PLAN_CONFIGURATION_KIND[$configuration_key]}"
        scope="${LWBS_PLAN_CONFIGURATION_SCOPE[$configuration_key]}"
        destination="${LWBS_PLAN_CONFIGURATION_DESTINATION[$configuration_key]}"
        source="${LWBS_PLAN_CONFIGURATION_SOURCE[$configuration_key]}"
        mode="${LWBS_PLAN_CONFIGURATION_MODE[$configuration_key]}"
        backup="${LWBS_PLAN_CONFIGURATION_BACKUP[$configuration_key]}"
        planned_action="${LWBS_PLAN_CONFIGURATION_ACTION[$configuration_key]}"

        if current_state="$(
            configuration_state \
                "$kind" \
                "$configuration_id" \
                "$destination" \
                "$source" \
                "$mode"
        )"; then
            :
        else
            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "unverifiable" \
                "state check failed"

            return 1
        fi

        if [[ "$planned_action" == "skip" ]]; then
            if [[ "$current_state" == "skip" ]]; then
                record_execution_result \
                    "$result_key" \
                    "configuration" \
                    "$module_id" \
                    "$configuration_id" \
                    "skipped" \
                    "desired configuration already present"

                continue
            fi

            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "failed" \
                "planned configuration state changed"

            return 1
        fi

        if [[ "$current_state" == "skip" ]]; then
            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "skipped" \
                "became satisfied before execution"

            continue
        fi

        if [[ "$current_state" == "update" &&
            "$backup" == "backup" ]]; then

            if configuration_create_backup \
                "$scope" \
                "$destination"; then
                :
            else
                exit_code=$?

                record_execution_result \
                    "$result_key" \
                    "configuration" \
                    "$module_id" \
                    "$configuration_id" \
                    "failed" \
                    "backup creation failed"

                return "$exit_code"
            fi
        fi

        if configuration_prepare_desired_file \
            "$kind" \
            "$configuration_id" \
            "$destination" \
            "$source" \
            desired_file; then
            :
        else
            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "failed" \
                "unable to prepare desired configuration"

            return 1
        fi

        if configuration_atomic_replace \
            "$scope" \
            "$destination" \
            "$desired_file" \
            "$mode"; then
            :
        else
            exit_code=$?
            rm -f -- "$desired_file"

            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "failed" \
                "atomic replacement failed"

            return "$exit_code"
        fi

        rm -f -- "$desired_file"

        if current_state="$(
            configuration_state \
                "$kind" \
                "$configuration_id" \
                "$destination" \
                "$source" \
                "$mode"
        )"; then
            :
        else
            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "unverifiable" \
                "post-write state check failed"

            return 1
        fi

        if [[ "$current_state" != "skip" ]]; then
            record_execution_result \
                "$result_key" \
                "configuration" \
                "$module_id" \
                "$configuration_id" \
                "failed" \
                "desired configuration was not reached"

            return 1
        fi

        record_execution_result \
            "$result_key" \
            "configuration" \
            "$module_id" \
            "$configuration_id" \
            "successful" \
            "desired configuration verified"

    done <<<"${LWBS_PLAN_MODULE_CONFIGURATIONS[$module_id]:-}"

    return 0
}

record_skipped_configuration_results() {
    local module_id="${1:-}"
    local configuration_id
    local result_key

    while IFS= read -r configuration_id; do
        [[ -z "$configuration_id" ]] && continue

        result_key="$(
            configuration_result_key \
                "$module_id" \
                "$configuration_id"
        )"

        record_execution_result \
            "$result_key" \
            "configuration" \
            "$module_id" \
            "$configuration_id" \
            "skipped" \
            "desired configuration already present"
    done <<<"${LWBS_PLAN_MODULE_CONFIGURATIONS[$module_id]:-}"
}

reset_configuration_execution_plan() {
    LWBS_PLAN_CONFIGURATION_ACTION_COUNT=0

    LWBS_PLAN_MODULE_CONFIGURATIONS=()
    LWBS_PLAN_CONFIGURATION_KIND=()
    LWBS_PLAN_CONFIGURATION_SCOPE=()
    LWBS_PLAN_CONFIGURATION_DESTINATION=()
    LWBS_PLAN_CONFIGURATION_SOURCE=()
    LWBS_PLAN_CONFIGURATION_MODE=()
    LWBS_PLAN_CONFIGURATION_BACKUP=()
    LWBS_PLAN_CONFIGURATION_ACTION=()
    LWBS_PLAN_CONFIGURATION_DESTINATION_OWNER=()
}
