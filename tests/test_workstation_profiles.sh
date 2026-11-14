#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# Source the complete bootstrap framework because these tests exercise the
# workstation profiles through normal profile and execution-plan resolution.
# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

reset_cli_profile_selections() {
    LWBS_REQUESTED_MODULES=()
    LWBS_EXCLUDED_MODULES=()
}

test_developer_profile_contract() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"
    reset_cli_profile_selections

    load_profile developer

    assert_equal \
        "developer" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "Developer Workstation" \
        "$LWBS_PROFILE_NAME"

    assert_equal \
        "4" \
        "${#LWBS_PROFILE_MODULES[@]}"

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\ncontainers-virtualization\ndatabase-tools' \
        "$modules"

    reset_profile_contract
}

test_security_profile_contract() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"
    reset_cli_profile_selections

    load_profile security

    assert_equal \
        "security" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "Security Workstation" \
        "$LWBS_PROFILE_NAME"

    assert_equal \
        "3" \
        "${#LWBS_PROFILE_MODULES[@]}"

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\nsecurity-tools' \
        "$modules"

    reset_profile_contract
}

test_developer_profile_dry_run_plan() {
    local temp_dir
    local output_file
    local output
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"
    reset_cli_profile_selections

    output_file="$temp_dir/developer-plan.out"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Mark every repository-managed dependency absent so the dry-run exposes
    # the complete developer workstation package plan.
    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    run_profile developer >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "18" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    modules="$(
        printf '%s\n' "${LWBS_PLAN_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\ncontainers-virtualization\ndatabase-tools' \
        "$modules"

    assert_contains \
        "$output" \
        "Developer Workstation"

    assert_contains \
        "$output" \
        "Common Utilities"

    assert_contains \
        "$output" \
        "Development Tools"

    assert_contains \
        "$output" \
        "Containers and Virtualization"

    assert_contains \
        "$output" \
        "Database Tools"

    assert_contains \
        "$output" \
        "build-essential [install]"

    assert_contains \
        "$output" \
        "docker.io [install]"

    assert_contains \
        "$output" \
        "postgresql-client [install]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

test_security_profile_dry_run_plan() {
    local temp_dir
    local output_file
    local output
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"
    reset_cli_profile_selections

    output_file="$temp_dir/security-plan.out"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Expose the complete repository-managed security workstation plan.
    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    # Fail2ban will not exist until its planned package installation has
    # completed, so service configuration must be deferred.
    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "absent"
    }

    run_profile security >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "17" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "1" \
        "$LWBS_PLAN_SERVICE_ACTION_COUNT"

    modules="$(
        printf '%s\n' "${LWBS_PLAN_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\nsecurity-tools' \
        "$modules"

    assert_contains \
        "$output" \
        "Security Workstation"

    assert_contains \
        "$output" \
        "Common Utilities"

    assert_contains \
        "$output" \
        "Development Tools"

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

test_developer_profile_can_be_extended_from_cli() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=(
        "desktop-media"
    )

    LWBS_EXCLUDED_MODULES=()

    load_profile developer

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\ncontainers-virtualization\ndatabase-tools\ndesktop-media' \
        "$modules"

    assert_equal \
        "5" \
        "${#LWBS_PROFILE_MODULES[@]}"

    reset_profile_contract
}

test_security_profile_can_exclude_development_tools() {
    local temp_dir
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_REQUESTED_MODULES=()

    LWBS_EXCLUDED_MODULES=(
        "development-tools"
    )

    load_profile security

    modules="$(
        printf '%s\n' "${LWBS_PROFILE_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\nsecurity-tools' \
        "$modules"

    assert_equal \
        "2" \
        "${#LWBS_PROFILE_MODULES[@]}"

    reset_profile_contract
}

run_test \
    "load the deterministic developer workstation profile" \
    test_developer_profile_contract

run_test \
    "load the deterministic security workstation profile" \
    test_security_profile_contract

run_test \
    "resolve the complete developer workstation dry-run plan" \
    test_developer_profile_dry_run_plan

run_test \
    "resolve the complete security workstation dry-run plan" \
    test_security_profile_dry_run_plan

run_test \
    "extend the developer profile through CLI module selection" \
    test_developer_profile_can_be_extended_from_cli

run_test \
    "allow explicit security profile module exclusion" \
    test_security_profile_can_exclude_development_tools

finish_tests
