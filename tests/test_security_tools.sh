#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# Source the complete bootstrap framework because these tests exercise the
# module through capability, service, profile, and execution-plan integration.
# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

create_security_test_profile() {
    local profile_directory="${1:-}"
    local profile_id="${2:-}"

    mkdir -p -- "$profile_directory"

    cat >"$profile_directory/$profile_id.sh" <<EOF_PROFILE
profile_id() {
    printf '%s\n' "$profile_id"
}

profile_name() {
    printf '%s\n' "Security Tools Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the security tools module for testing."
}

profile_modules() {
    printf '%s\n' "security-tools"
}
EOF_PROFILE
}

test_security_tools_module_contract() {
    local temp_dir
    local capabilities
    local services

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module security-tools

    assert_equal \
        "security-tools" \
        "$LWBS_MODULE_ID"

    assert_equal \
        "Security Tools" \
        "$LWBS_MODULE_NAME"

    assert_equal \
        "2" \
        "${#LWBS_MODULE_CAPABILITIES[@]}"

    capabilities="$(
        printf '%s\n' "${LWBS_MODULE_CAPABILITIES[@]}"
    )"

    assert_equal \
        $'host-intrusion-protection\nusb-device-control' \
        "$capabilities"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"

    assert_equal \
        "1" \
        "${#LWBS_MODULE_SERVICES[@]}"

    services="$(
        printf '%s\n' "${LWBS_MODULE_SERVICES[@]}"
    )"

    assert_equal \
        "fail2ban.service enabled active never" \
        "$services"

    if ! declare -F module_verify >/dev/null 2>&1; then
        printf 'security-tools does not provide module_verify.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_security_tools_resolve_on_supported_distros() {
    local temp_dir
    local distro
    local resolved

    local -a resolved_packages=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    for distro in ubuntu debian kali; do
        load_capability_map "$distro"

        resolved_packages=()

        resolve_capabilities \
            resolved_packages \
            host-intrusion-protection \
            usb-device-control

        resolved="$(
            printf '%s\n' "${resolved_packages[@]}"
        )"

        assert_equal \
            $'fail2ban\nusbguard' \
            "$resolved" \
            "security capability mapping differs for $distro"

        reset_capability_map
    done
}

test_security_tools_verification_succeeds() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module security-tools

    # Verification dependency mocked so this test does not depend on security
    # utilities installed on the developer workstation.
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 0
    }

    module_verify

    reset_module_contract
}

test_security_tools_verification_detects_missing_command() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module security-tools

    # Simulate an installed package set whose USBGuard command is unavailable.
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "usbguard" ]]
    }

    if module_verify >/dev/null 2>&1; then
        printf 'module_verify accepted a missing security command.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_security_tools_can_be_selected_by_profile() {
    local temp_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"

    create_security_test_profile \
        "$profile_dir" \
        "security-test-profile"

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    load_profile security-test-profile

    assert_equal \
        "security-test-profile" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "1" \
        "${#LWBS_PROFILE_MODULES[@]}"

    assert_equal \
        "security-tools" \
        "${LWBS_PROFILE_MODULES[0]}"

    reset_profile_contract
}

test_security_tools_dry_run_execution_plan() {
    local temp_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/execution-plan.out"

    create_security_test_profile \
        "$profile_dir" \
        "security-test-profile"

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Planning needs package state but must not perform installation during
    # dry-run. Mark both security packages absent.
    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    # The Fail2ban service does not exist yet because its package is planned
    # for installation. The service framework must defer configuration.
    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "absent"
    }

    run_profile security-test-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "2" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "1" \
        "$LWBS_PLAN_SERVICE_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_contains \
        "$output" \
        "Security Tools"

    assert_contains \
        "$output" \
        "fail2ban [install]"

    assert_contains \
        "$output" \
        "usbguard [install]"

    assert_contains \
        "$output" \
        "fail2ban.service [configure after install: enabled=enabled active=active]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

test_security_tools_skip_satisfied_installation() {
    local temp_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/execution-plan.out"

    create_security_test_profile \
        "$profile_dir" \
        "security-satisfied-profile"

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # All repository-managed security packages are already installed.
    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "installed"
    }

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

    run_profile security-satisfied-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "0" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SERVICE_ACTION_COUNT"

    assert_equal \
        "3" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_contains \
        "$output" \
        "fail2ban [installed, skip]"

    assert_contains \
        "$output" \
        "usbguard [installed, skip]"

    assert_contains \
        "$output" \
        "fail2ban.service [state satisfied, skip]"
}

test_usbguard_is_not_activated_implicitly() {
    local temp_dir
    local service_requirement

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module security-tools

    for service_requirement in "${LWBS_MODULE_SERVICES[@]}"; do
        if [[ "$service_requirement" == usbguard.service* ]]; then
            printf 'security-tools unexpectedly activates USBGuard.\n' >&2
            return 1
        fi
    done

    reset_module_contract
}

run_test \
    "load the security tools module contract" \
    test_security_tools_module_contract

run_test \
    "resolve security capabilities on all supported distros" \
    test_security_tools_resolve_on_supported_distros

run_test \
    "verify available security tools" \
    test_security_tools_verification_succeeds

run_test \
    "detect a missing security command during verification" \
    test_security_tools_verification_detects_missing_command

run_test \
    "select security tools through a workstation profile" \
    test_security_tools_can_be_selected_by_profile

run_test \
    "resolve security tools through a dry-run execution plan" \
    test_security_tools_dry_run_execution_plan

run_test \
    "skip already satisfied security requirements" \
    test_security_tools_skip_satisfied_installation

run_test \
    "keep USBGuard enforcement explicit" \
    test_usbguard_is_not_activated_implicitly

finish_tests