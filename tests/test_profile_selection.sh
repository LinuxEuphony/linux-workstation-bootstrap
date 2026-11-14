#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

test_default_profile_contract() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=()
    LWBS_EXCLUDED_MODULES=()

    load_profile default

    assert_equal \
        "default" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "Default Workstation" \
        "$LWBS_PROFILE_NAME"

    assert_equal \
        "3" \
        "${#LWBS_PROFILE_MODULES[@]}"

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndesktop-media\nhardware-power' \
        "$modules"

    reset_profile_contract
}

test_list_available_profiles() {
    local output

    output="$(list_available_profiles)"

    assert_contains \
        "$output" \
        "default"

    assert_contains \
        "$output" \
        "Default Workstation"
}

test_add_modules_without_duplication() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=(
        "development-tools"
        "common-utilities"
    )

    LWBS_EXCLUDED_MODULES=()

    load_profile default

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndesktop-media\nhardware-power\ndevelopment-tools' \
        "$modules"

    assert_equal \
        "4" \
        "${#LWBS_PROFILE_MODULES[@]}"

    reset_profile_contract
}

test_exclude_profile_module() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=()
    LWBS_EXCLUDED_MODULES=(
        "desktop-media"
    )

    load_profile default

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\nhardware-power' \
        "$modules"

    reset_profile_contract
}

test_unknown_added_module_fails() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=(
        "definitely-missing-module"
    )

    LWBS_EXCLUDED_MODULES=()

    if load_profile default >/dev/null 2>&1; then
        printf 'Unknown requested module was accepted.\n' >&2
        return 1
    fi
}

test_unknown_profile_fails() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=()
    LWBS_EXCLUDED_MODULES=()

    if load_profile definitely-missing-profile >/dev/null 2>&1; then
        printf 'Unknown workstation profile was accepted.\n' >&2
        return 1
    fi
}

test_cli_module_selection_reaches_execution_plan() {
    local temp_dir
    local output_file
    local output
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    output_file="$temp_dir/execution-plan.out"

    LWBS_REQUESTED_MODULES=(
        "development-tools"
    )

    LWBS_EXCLUDED_MODULES=(
        "desktop-media"
    )

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Hardware-specific capabilities are intentionally absent so this test
    # focuses only on profile and CLI module resolution.
    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 1
    }

    # Every repository-managed capability is treated as absent so the plan
    # exposes the complete final module selection.
    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    run_profile default >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "15" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    modules="$(
        printf '%s\n' "${LWBS_PLAN_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\nhardware-power\ndevelopment-tools' \
        "$modules"

    assert_contains \
        "$output" \
        "Default Workstation"

    assert_contains \
        "$output" \
        "Common Utilities"

    assert_contains \
        "$output" \
        "Hardware and Power Management"

    assert_contains \
        "$output" \
        "Development Tools"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

run_test \
    "load the deterministic default workstation profile" \
    test_default_profile_contract

run_test \
    "list available workstation profiles" \
    test_list_available_profiles

run_test \
    "add modules without duplicate execution" \
    test_add_modules_without_duplication

run_test \
    "exclude modules from a selected profile" \
    test_exclude_profile_module

run_test \
    "reject an unknown explicitly requested module" \
    test_unknown_added_module_fails

run_test \
    "reject an unknown workstation profile" \
    test_unknown_profile_fails

run_test \
    "apply CLI module selection to the final execution plan" \
    test_cli_module_selection_reaches_execution_plan

finish_tests
