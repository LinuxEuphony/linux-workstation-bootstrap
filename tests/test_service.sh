#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# Source the complete bootstrap framework because these tests exercise service
# declarations through module loading and execution planning.
# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

create_service_test_profile() {
    local profile_directory="${1:-}"
    local profile_id="${2:-}"
    local module_id="${3:-}"

    mkdir -p -- "$profile_directory"

    cat >"$profile_directory/$profile_id.sh" <<EOF_PROFILE
profile_id() {
    printf '%s\n' "$profile_id"
}

profile_name() {
    printf '%s\n' "Service Test Profile"
}

profile_description() {
    printf '%s\n' "Selects a service test module."
}

profile_modules() {
    printf '%s\n' "$module_id"
}
EOF_PROFILE
}

test_parse_valid_service_requirement() {
    local service_name=""
    local enabled_state=""
    local active_state=""
    local restart_policy=""

    parse_service_requirement \
        "docker.service enabled active on-change" \
        service_name \
        enabled_state \
        active_state \
        restart_policy

    assert_equal "docker.service" "$service_name"
    assert_equal "enabled" "$enabled_state"
    assert_equal "active" "$active_state"
    assert_equal "on-change" "$restart_policy"
}

test_reject_invalid_service_requirements() {
    local service_name=""
    local enabled_state=""
    local active_state=""
    local restart_policy=""

    if parse_service_requirement \
        "docker enabled active never" \
        service_name \
        enabled_state \
        active_state \
        restart_policy \
        >/dev/null 2>&1; then

        printf 'Service requirement accepted a unit without .service.\n' >&2
        return 1
    fi

    if parse_service_requirement \
        "docker.service enabled inactive on-change" \
        service_name \
        enabled_state \
        active_state \
        restart_policy \
        >/dev/null 2>&1; then

        printf 'Service requirement accepted on-change for an inactive target.\n' >&2
        return 1
    fi
}

test_detect_systemd_service_manager() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    mkdir -p -- "$temp_dir/systemd/system"
    LWBS_SYSTEMD_RUNTIME_DIR_OVERRIDE="$temp_dir/systemd/system"

    # Mocked command lookup used indirectly by service_manager_available().
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        [[ "${1:-}" == "systemctl" ]]
    }

    service_manager_available

    LWBS_SYSTEMD_RUNTIME_DIR_OVERRIDE="$temp_dir/missing"

    if service_manager_available; then
        printf 'Service manager accepted a missing systemd runtime directory.\n' >&2
        return 1
    fi
}

test_query_service_state() {
    local presence
    local enabled_state
    local active_state

    # Controlled systemd environment and responses for read-only state checks.
    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    systemctl() {
        case "${1:-}" in
            show)
                printf '%s\n' "loaded"
                ;;
            is-enabled)
                printf '%s\n' "enabled"
                ;;
            is-active)
                printf '%s\n' "active"
                ;;
            *)
                return 1
                ;;
        esac
    }

    presence="$(query_service_presence example.service)"
    enabled_state="$(query_service_enabled_state example.service)"
    active_state="$(query_service_active_state example.service)"

    assert_equal "present" "$presence"
    assert_equal "enabled" "$enabled_state"
    assert_equal "active" "$active_state"
}

test_service_actions_use_privileged_execution() {
    local captured_actions=""

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # Capture privileged calls instead of changing the developer workstation.
    # shellcheck disable=SC2317,SC2329
    run_privileged_command() {
        captured_actions+="$*"$'\n'
    }

    service_enable example.service
    service_disable example.service
    service_start example.service
    service_stop example.service
    service_restart example.service

    assert_contains "$captured_actions" "systemctl enable example.service"
    assert_contains "$captured_actions" "systemctl disable example.service"
    assert_contains "$captured_actions" "systemctl start example.service"
    assert_contains "$captured_actions" "systemctl stop example.service"
    assert_contains "$captured_actions" "systemctl restart example.service"
}

test_module_loads_service_requirements() {
    local temp_dir
    local module_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    module_dir="$temp_dir/modules"
    mkdir -p -- "$module_dir"

    cat >"$module_dir/service-only.sh" <<'EOF_MODULE'
module_id() {
    printf '%s\n' "service-only"
}

module_name() {
    printf '%s\n' "Service Only"
}

module_description() {
    printf '%s\n' "Declares only managed service state."
}

module_capabilities() {
    return 0
}

module_services() {
    printf '%s\n' "example.service enabled active never"
}
EOF_MODULE

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"

    load_module service-only

    assert_equal "1" "${#LWBS_MODULE_SERVICES[@]}"
    assert_equal \
        "example.service enabled active never" \
        "${LWBS_MODULE_SERVICES[0]}"

    reset_module_contract
}

test_plan_service_state_changes() {
    local temp_dir
    local module_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    module_dir="$temp_dir/modules"
    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/plan.out"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/service-plan.sh" <<'EOF_MODULE'
module_id() {
    printf '%s\n' "service-plan"
}

module_name() {
    printf '%s\n' "Service Plan"
}

module_description() {
    printf '%s\n' "Tests managed service planning."
}

module_capabilities() {
    return 0
}

module_services() {
    printf '%s\n' "example.service enabled active never"
}
EOF_MODULE

    create_service_test_profile \
        "$profile_dir" \
        "service-plan-profile" \
        "service-plan"

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"
    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"
    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_CAPABILITY_PROFILE="ubuntu"
    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "present"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_enabled_state() {
        printf '%s\n' "disabled"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_active_state() {
        printf '%s\n' "inactive"
    }

    run_profile service-plan-profile >"$output_file"
    output="$(<"$output_file")"

    assert_equal "previewed" "$LWBS_PLAN_STATUS"
    assert_equal "2" "$LWBS_PLAN_SERVICE_ACTION_COUNT"
    assert_contains "$output" "example.service [enable,start]"
}

test_skip_service_restart_without_module_changes() {
    local temp_dir
    local module_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    module_dir="$temp_dir/modules"
    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/plan.out"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/service-stable.sh" <<'EOF_MODULE'
module_id() {
    printf '%s\n' "service-stable"
}

module_name() {
    printf '%s\n' "Service Stable"
}

module_description() {
    printf '%s\n' "Tests restart suppression."
}

module_capabilities() {
    return 0
}

module_services() {
    printf '%s\n' "example.service enabled active on-change"
}
EOF_MODULE

    create_service_test_profile \
        "$profile_dir" \
        "service-stable-profile" \
        "service-stable"

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"
    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"
    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_CAPABILITY_PROFILE="ubuntu"
    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "present"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_enabled_state() {
        printf '%s\n' "enabled"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_active_state() {
        printf '%s\n' "active"
    }

    run_profile service-stable-profile >"$output_file"
    output="$(<"$output_file")"

    assert_equal "0" "$LWBS_PLAN_SERVICE_ACTION_COUNT"
    assert_contains "$output" "example.service [state satisfied, skip]"
}

test_plan_restart_after_module_change() {
    local temp_dir
    local module_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    module_dir="$temp_dir/modules"
    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/plan.out"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/service-restart.sh" <<'EOF_MODULE'
module_id() {
    printf '%s\n' "service-restart"
}

module_name() {
    printf '%s\n' "Service Restart"
}

module_description() {
    printf '%s\n' "Tests restart-on-change planning."
}

module_capabilities() {
    return 0
}

module_services() {
    printf '%s\n' "example.service enabled active on-change"
}

module_apply() {
    return 0
}
EOF_MODULE

    create_service_test_profile \
        "$profile_dir" \
        "service-restart-profile" \
        "service-restart"

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"
    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"
    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_CAPABILITY_PROFILE="ubuntu"
    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "present"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_enabled_state() {
        printf '%s\n' "enabled"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_active_state() {
        printf '%s\n' "active"
    }

    run_profile service-restart-profile >"$output_file"
    output="$(<"$output_file")"

    assert_equal "1" "$LWBS_PLAN_SERVICE_ACTION_COUNT"
    assert_contains "$output" "example.service [restart]"
}

test_missing_service_without_planned_creator_fails() {
    local temp_dir
    local module_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    module_dir="$temp_dir/modules"
    profile_dir="$temp_dir/profiles"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/service-missing.sh" <<'EOF_MODULE'
module_id() {
    printf '%s\n' "service-missing"
}

module_name() {
    printf '%s\n' "Service Missing"
}

module_description() {
    printf '%s\n' "Tests missing required service handling."
}

module_capabilities() {
    return 0
}

module_services() {
    printf '%s\n' "missing.service enabled active never"
}
EOF_MODULE

    create_service_test_profile \
        "$profile_dir" \
        "service-missing-profile" \
        "service-missing"

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"
    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"
    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_CAPABILITY_PROFILE="ubuntu"
    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "absent"
    }

    if run_profile service-missing-profile >/dev/null 2>&1; then
        printf 'Execution plan accepted a missing required service.\n' >&2
        return 1
    fi
}

test_defer_service_state_until_package_install() {
    local temp_dir
    local module_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    module_dir="$temp_dir/modules"
    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/plan.out"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/service-package.sh" <<'EOF_MODULE'
module_id() {
    printf '%s\n' "service-package"
}

module_name() {
    printf '%s\n' "Service Package"
}

module_description() {
    printf '%s\n' "Tests service creation by planned package installation."
}

module_capabilities() {
    printf '%s\n' "curl"
}

module_services() {
    printf '%s\n' "example.service enabled active never"
}
EOF_MODULE

    create_service_test_profile \
        "$profile_dir" \
        "service-package-profile" \
        "service-package"

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"
    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"
    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    load_capability_map ubuntu

    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "absent"
    }

    run_profile service-package-profile >"$output_file"
    output="$(<"$output_file")"

    assert_equal "1" "$LWBS_PLAN_INSTALL_ACTION_COUNT"
    assert_equal "1" "$LWBS_PLAN_SERVICE_ACTION_COUNT"
    assert_contains \
        "$output" \
        "example.service [configure after install: enabled=enabled active=active]"
}

test_execute_service_actions_and_verify_state() {
    local temp_dir
    local module_id="service-execution"
    local service_name="example.service"
    local service_key
    local result_key
    local mock_enabled="disabled"
    local mock_active="inactive"

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"
    setup_test_logging "$temp_dir"

    reset_execution_results
    reset_service_execution_plan

    LWBS_PLAN_MODULE_SERVICES["$module_id"]="$service_name enabled active never"

    service_key="$(execution_plan_service_key "$module_id" "$service_name")"
    result_key="$(service_result_key "$module_id" "$service_name")"

    LWBS_PLAN_SERVICE_ACTIONS["$service_key"]="enable,start"
    LWBS_PLAN_MODULE_HAS_APPLY["$module_id"]="false"

    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "present"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_enabled_state() {
        printf '%s\n' "$mock_enabled"
    }

    # shellcheck disable=SC2317,SC2329
    query_service_active_state() {
        printf '%s\n' "$mock_active"
    }

    # shellcheck disable=SC2317,SC2329
    service_enable() {
        mock_enabled="enabled"
    }

    # shellcheck disable=SC2317,SC2329
    service_start() {
        mock_active="active"
    }

    execute_planned_service_actions "$module_id"

    assert_equal "enabled" "$mock_enabled"
    assert_equal "active" "$mock_active"
    assert_equal "successful" "${LWBS_RESULT_STATUS[$result_key]}"
}

run_test \
    "parse a valid service requirement" \
    test_parse_valid_service_requirement

run_test \
    "reject invalid service requirements" \
    test_reject_invalid_service_requirements

run_test \
    "detect an available systemd service manager" \
    test_detect_systemd_service_manager

run_test \
    "query managed service state" \
    test_query_service_state

run_test \
    "route service actions through privileged execution" \
    test_service_actions_use_privileged_execution

run_test \
    "load declarative module service requirements" \
    test_module_loads_service_requirements

run_test \
    "plan required service state changes" \
    test_plan_service_state_changes

run_test \
    "avoid restart when no module change is planned" \
    test_skip_service_restart_without_module_changes

run_test \
    "plan restart when relevant module changes are planned" \
    test_plan_restart_after_module_change

run_test \
    "reject a missing service without a planned creator" \
    test_missing_service_without_planned_creator_fails

run_test \
    "defer service state until planned package installation" \
    test_defer_service_state_until_package_install

run_test \
    "execute and verify required service state" \
    test_execute_service_actions_and_verify_state

finish_tests
