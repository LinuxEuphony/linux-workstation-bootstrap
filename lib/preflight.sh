#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Bootstrap preflight validation.
#
# Preflight evaluates the fully resolved workstation plan before any
# installation or configuration action begins.
#
# The layer:
# 1. Validates the selected distribution adapter and environment.
# 2. Validates the selected distro and architecture combination.
# 3. Verifies persistent state and logging paths remain usable.
# 4. Verifies privilege escalation when planned actions require it.
# 5. Verifies service-manager availability for planned service changes.
# 6. Supports declarative module and external-installer requirements.
# 7. Performs network probes only when a planned action explicitly requires
#    network connectivity.
# 8. Aggregates blocking failures rather than stopping at the first problem.
#
# Supported contributed requirements:
#
#   privilege
#   command:<command>
#   network:<host>:<port>
#
# Modules may optionally expose:
#
#   module_preflight_requirements
#
# External installers may optionally expose:
#
#   external_preflight_requirements
#
# Requirement functions must be read-only and print one requirement per line.
#
# shellcheck disable=SC2154,SC2317,SC2329

LWBS_PREFLIGHT_STATUS="empty"

declare -a LWBS_PREFLIGHT_FAILURES=()
declare -A LWBS_PREFLIGHT_FAILURE_SET=()
declare -A LWBS_PREFLIGHT_NETWORK_PROBES=()

reset_preflight_state() {
    LWBS_PREFLIGHT_STATUS="empty"
    LWBS_PREFLIGHT_FAILURES=()
    LWBS_PREFLIGHT_FAILURE_SET=()
    LWBS_PREFLIGHT_NETWORK_PROBES=()
}

preflight_add_failure() {
    local message="${1:-}"

    if [[ -z "$message" ]]; then
        return 2
    fi

    if [[ -n "${LWBS_PREFLIGHT_FAILURE_SET[$message]+defined}" ]]; then
        return 0
    fi

    LWBS_PREFLIGHT_FAILURE_SET["$message"]=1
    LWBS_PREFLIGHT_FAILURES+=("$message")

    if [[ -n "${LWBS_LOG_FILE:-}" ]]; then
        log_error "Preflight failure: $message" || true
    fi

    return 0
}

preflight_is_root() {
    ((EUID == 0))
}

preflight_architecture_is_supported() {
    local distro_profile="${1:-}"
    local architecture="${2:-}"
    local supported_architectures
    local supported_architecture

    supported_architectures="${LWBS_DISTRO_SUPPORTED_ARCHITECTURES["$distro_profile"]:-}"

    if [[ -z "$supported_architectures" ]]; then
        return 1
    fi

    for supported_architecture in $supported_architectures; do
        if [[ "$architecture" == "$supported_architecture" ]]; then
            return 0
        fi
    done

    return 1
}

preflight_check_architecture() {
    local distro_profile="${LWBS_PLAN_DISTRO_PROFILE:-}"
    local architecture="${SYSTEM_ARCH:-}"

    if [[ -z "$distro_profile" ]]; then
        preflight_add_failure \
            "The resolved execution plan does not identify a distribution profile."

        return 0
    fi

    if [[ -z "$architecture" ]]; then
        preflight_add_failure \
            "System architecture detection is unavailable."

        return 0
    fi

    if preflight_architecture_is_supported \
        "$distro_profile" \
        "$architecture"; then

        return 0
    fi

    preflight_add_failure \
        "Architecture $architecture is not supported by the $distro_profile installation profile."

    return 0
}

preflight_check_distro_adapter() {
    if [[ -z "${DISTRO_ADAPTER_PROFILE:-}" ]]; then
        preflight_add_failure \
            "No distribution adapter is loaded."

        return 0
    fi

    if [[ "${LWBS_PLAN_DISTRO_PROFILE:-}" != "$DISTRO_ADAPTER_PROFILE" ]]; then
        preflight_add_failure \
            "The resolved plan distribution does not match the loaded distribution adapter."

        return 0
    fi

    if validate_distro_adapter; then
        :
    else
        preflight_add_failure \
            "The selected distribution adapter does not satisfy the required adapter contract."

        return 0
    fi

    # Revalidate the adapter environment against the final resolved plan.
    # Current distro adapters verify the required package-management commands
    # and expected package-manager family without modifying the system.
    if distro_validate_environment; then
        :
    else
        preflight_add_failure \
            "The selected distribution adapter environment is not ready for execution."
    fi

    return 0
}

preflight_check_logging_paths() {
    if [[ -z "${LWBS_STATE_DIR:-}" ||
        ! -d "$LWBS_STATE_DIR" ||
        ! -w "$LWBS_STATE_DIR" ]]; then

        preflight_add_failure \
            "Application state directory is unavailable or not writable: ${LWBS_STATE_DIR:-unset}"
    fi

    if [[ -z "${LWBS_LOG_DIR:-}" ||
        ! -d "$LWBS_LOG_DIR" ||
        ! -w "$LWBS_LOG_DIR" ]]; then

        preflight_add_failure \
            "Application log directory is unavailable or not writable: ${LWBS_LOG_DIR:-unset}"
    fi

    if [[ -z "${LWBS_LOG_FILE:-}" ||
        ! -f "$LWBS_LOG_FILE" ||
        ! -w "$LWBS_LOG_FILE" ]]; then

        preflight_add_failure \
            "Session log file is unavailable or not writable: ${LWBS_LOG_FILE:-unset}"
    fi

    return 0
}

preflight_module_has_service_actions() {
    local module_id="${1:-}"
    local service_requirement
    local service_name
    local enabled_state
    local active_state
    local restart_policy
    local service_key
    local planned_action

    while IFS= read -r service_requirement; do
        [[ -z "$service_requirement" ]] && continue

        parse_service_requirement \
            "$service_requirement" \
            service_name \
            enabled_state \
            active_state \
            restart_policy

        service_key="$(
            execution_plan_service_key \
                "$module_id" \
                "$service_name"
        )"

        planned_action="${LWBS_PLAN_SERVICE_ACTIONS[$service_key]:-skip}"

        if [[ "$planned_action" != "skip" ]]; then
            return 0
        fi
    done <<<"${LWBS_PLAN_MODULE_SERVICES[$module_id]:-}"

    return 1
}

preflight_module_has_actions() {
    local module_id="${1:-}"

    if module_has_planned_changes "$module_id"; then
        return 0
    fi

    if preflight_module_has_service_actions "$module_id"; then
        return 0
    fi

    return 1
}

preflight_plan_requires_privilege() {
    local module_id

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        if [[ -n "${LWBS_PLAN_MODULE_INSTALL_PACKAGES[$module_id]:-}" ]]; then
            return 0
        fi

        if preflight_module_has_service_actions "$module_id"; then
            return 0
        fi
    done

    return 1
}

preflight_require_privilege() {
    local owner="${1:-Execution plan}"

    if preflight_is_root; then
        return 0
    fi

    if command_exists sudo; then
        return 0
    fi

    preflight_add_failure \
        "$owner requires root privileges, but sudo is unavailable."

    return 0
}

preflight_check_required_privilege() {
    if ! preflight_plan_requires_privilege; then
        return 0
    fi

    preflight_require_privilege "Execution plan"
}

preflight_check_service_manager() {
    if ((LWBS_PLAN_SERVICE_ACTION_COUNT == 0)); then
        return 0
    fi

    if service_manager_available; then
        return 0
    fi

    preflight_add_failure \
        "The execution plan contains service changes, but the systemd service manager is unavailable."

    return 0
}

preflight_network_available() {
    local host="${1:-}"
    local port="${2:-}"
    local network_command

    if [[ -z "$host" ||
        ! "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ||
        ! "$port" =~ ^[0-9]+$ ||
        "$port" -lt 1 ||
        "$port" -gt 65535 ]]; then

        return 2
    fi

    printf -v network_command \
        'exec 3<>"/dev/tcp/%s/%s"' \
        "$host" \
        "$port"

    timeout \
        5 \
        bash \
        -c "$network_command" \
        >/dev/null 2>&1
}

preflight_check_network_requirement() {
    local owner="${1:-}"
    local host="${2:-}"
    local port="${3:-}"
    local probe_key
    local previous_result

    probe_key="$host:$port"
    previous_result="${LWBS_PREFLIGHT_NETWORK_PROBES[$probe_key]:-}"

    case "$previous_result" in
        passed | failed)
            return 0
            ;;
    esac

    if ! command_exists timeout; then
        LWBS_PREFLIGHT_NETWORK_PROBES["$probe_key"]="failed"

        preflight_add_failure \
            "$owner requires network validation for $probe_key, but the timeout command is unavailable."

        return 0
    fi

    if preflight_network_available "$host" "$port"; then
        LWBS_PREFLIGHT_NETWORK_PROBES["$probe_key"]="passed"

        if [[ -n "${LWBS_LOG_FILE:-}" ]]; then
            log_info \
                "Preflight network probe succeeded: target=$probe_key owner=$owner"
        fi

        return 0
    fi

    LWBS_PREFLIGHT_NETWORK_PROBES["$probe_key"]="failed"

    preflight_add_failure \
        "$owner requires network connectivity to $probe_key, but the endpoint is unreachable."

    return 0
}

preflight_process_requirement() {
    local owner="${1:-}"
    local requirement="${2:-}"
    local command_name
    local network_target
    local host
    local port

    if [[ -z "$owner" || -z "$requirement" ]]; then
        preflight_add_failure \
            "An empty preflight requirement was declared."

        return 0
    fi

    case "$requirement" in
        privilege)
            preflight_require_privilege "$owner"
            ;;

        command:*)
            command_name="${requirement#command:}"

            if [[ ! "$command_name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
                preflight_add_failure \
                    "$owner declared an invalid command requirement: $requirement"

                return 0
            fi

            if ! command_exists "$command_name"; then
                preflight_add_failure \
                    "$owner requires command '$command_name', but it is unavailable."
            fi
            ;;

        network:*)
            network_target="${requirement#network:}"

            if [[ "$network_target" != *:* ]]; then
                preflight_add_failure \
                    "$owner declared an invalid network requirement: $requirement"

                return 0
            fi

            host="${network_target%:*}"
            port="${network_target##*:}"

            if [[ ! "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ||
                ! "$port" =~ ^[0-9]+$ ||
                "$port" -lt 1 ||
                "$port" -gt 65535 ]]; then

                preflight_add_failure \
                    "$owner declared an invalid network requirement: $requirement"

                return 0
            fi

            preflight_check_network_requirement \
                "$owner" \
                "$host" \
                "$port"
            ;;

        *)
            preflight_add_failure \
                "$owner declared an unsupported preflight requirement: $requirement"
            ;;
    esac

    return 0
}

preflight_read_module_requirements() (
    local module_id="${1:-}"
    local exit_code

    if load_module "$module_id"; then
        :
    else
        exit_code=$?
        exit "$exit_code"
    fi

    if declare -F module_preflight_requirements >/dev/null 2>&1; then
        module_preflight_requirements
    fi
)

preflight_collect_module_requirements() {
    local module_id
    local module_name
    local requirements
    local requirement
    local exit_code

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        if ! preflight_module_has_actions "$module_id"; then
            continue
        fi

        module_name="${LWBS_PLAN_MODULE_NAMES[$module_id]:-$module_id}"

        if requirements="$(
            preflight_read_module_requirements \
                "$module_id"
        )"; then
            :
        else
            exit_code=$?

            preflight_add_failure \
                "Unable to evaluate preflight requirements for module $module_id."

            if [[ -n "${LWBS_LOG_FILE:-}" ]]; then
                log_error \
                    "Module preflight requirement evaluation failed: module=$module_id exit_code=$exit_code"
            fi

            continue
        fi

        while IFS= read -r requirement; do
            [[ -z "$requirement" ]] && continue

            preflight_process_requirement \
                "Module '$module_name'" \
                "$requirement"
        done <<<"$requirements"
    done

    return 0
}

preflight_read_external_requirements() (
    local installer_id="${1:-}"
    local exit_code

    if load_external_installer "$installer_id"; then
        :
    else
        exit_code=$?
        exit "$exit_code"
    fi

    if declare -F external_preflight_requirements >/dev/null 2>&1; then
        external_preflight_requirements
    fi
)

preflight_collect_external_requirements() {
    local module_id
    local installer_id
    local external_key
    local requirements
    local requirement
    local exit_code

    for module_id in "${LWBS_PLAN_MODULES[@]}"; do
        while IFS= read -r installer_id; do
            [[ -z "$installer_id" ]] && continue

            external_key="$(
                execution_plan_external_key \
                    "$module_id" \
                    "$installer_id"
            )"

            if [[ "${LWBS_PLAN_EXTERNAL_ACTIONS[$external_key]:-}" != "install" ]]; then
                continue
            fi

            if requirements="$(
                preflight_read_external_requirements \
                    "$installer_id"
            )"; then
                :
            else
                exit_code=$?

                preflight_add_failure \
                    "Unable to evaluate preflight requirements for external installer $installer_id."

                if [[ -n "${LWBS_LOG_FILE:-}" ]]; then
                    log_error \
                        "External preflight requirement evaluation failed: installer=$installer_id exit_code=$exit_code"
                fi

                continue
            fi

            while IFS= read -r requirement; do
                [[ -z "$requirement" ]] && continue

                preflight_process_requirement \
                    "External installer '$installer_id'" \
                    "$requirement"
            done <<<"$requirements"
        done <<<"${LWBS_PLAN_MODULE_EXTERNALS[$module_id]:-}"
    done

    return 0
}

show_preflight_result() {
    local failure

    printf '\nPreflight validation\n\n'

    if ((${#LWBS_PREFLIGHT_FAILURES[@]} == 0)); then
        printf '  Status       : passed\n\n'
        return 0
    fi

    printf '  Status       : failed\n'
    printf '  Blocking issues:\n'

    for failure in "${LWBS_PREFLIGHT_FAILURES[@]}"; do
        printf '    - %s\n' "$failure"
    done

    printf '\n'

    return 0
}

run_preflight_validation() {
    reset_preflight_state
    LWBS_PREFLIGHT_STATUS="running"

    if [[ "${LWBS_PLAN_STATUS:-}" != "resolved" ]]; then
        preflight_add_failure \
            "Preflight requires a fully resolved execution plan."

        LWBS_PREFLIGHT_STATUS="failed"
        show_preflight_result

        return 1
    fi

    log_info \
        "Preflight validation started: profile=$LWBS_PLAN_PROFILE_ID distro=$LWBS_PLAN_DISTRO_PROFILE"

    preflight_check_distro_adapter
    preflight_check_architecture
    preflight_check_logging_paths
    preflight_check_required_privilege
    preflight_check_service_manager
    preflight_collect_module_requirements
    preflight_collect_external_requirements

    if ((${#LWBS_PREFLIGHT_FAILURES[@]} > 0)); then
        LWBS_PREFLIGHT_STATUS="failed"

        log_error \
            "Preflight validation failed: failures=${#LWBS_PREFLIGHT_FAILURES[@]}"

        show_preflight_result

        return 1
    fi

    LWBS_PREFLIGHT_STATUS="passed"

    log_info \
        "Preflight validation passed: profile=$LWBS_PLAN_PROFILE_ID"

    show_preflight_result

    return 0
}

validate_profile_preflight() {
    local profile_id="${1:-}"
    local exit_code

    if [[ -z "$profile_id" ]]; then
        printf 'Error: preflight requires a workstation profile.\n' >&2
        return 2
    fi

    log_info \
        "Resolving workstation profile for preflight: profile=$profile_id"

    if build_profile_execution_plan "$profile_id"; then
        :
    else
        exit_code=$?

        LWBS_PREFLIGHT_STATUS="failed"

        log_error \
            "Unable to resolve execution plan for preflight: profile=$profile_id exit_code=$exit_code"

        reset_execution_plan

        return "$exit_code"
    fi

    if run_preflight_validation; then
        exit_code=0
    else
        exit_code=$?
    fi

    # Preflight resolution is read-only. Reset the temporary resolved plan so
    # normal execution planning begins from a clean state afterward.
    reset_execution_plan

    return "$exit_code"
}
