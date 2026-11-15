#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

prepare_restart_test() {
    local temp_dir="${1:-}"

    setup_test_logging "$temp_dir"

    reset_execution_plan
    reset_execution_results
    reset_restart_tracking

    LWBS_DRY_RUN=false
}

test_parse_restart_requirement() {
    local temp_dir
    local type
    local target
    local reason

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    parse_restart_requirement \
        "reboot|system|Kernel changes require a reboot" \
        type \
        target \
        reason

    assert_equal "reboot" "$type"
    assert_equal "system" "$target"
    assert_equal "Kernel changes require a reboot" "$reason"
}

test_reject_invalid_restart_target() {
    local temp_dir
    local type
    local target
    local reason

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    if parse_restart_requirement \
        "logout|system|Invalid target" \
        type \
        target \
        reason \
        >/dev/null 2>&1; then

        printf 'Invalid restart target was accepted.\n' >&2
        return 1
    fi
}

test_deduplicate_restart_requirements() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    restart_add_planned_requirement \
        reboot \
        system \
        "Kernel changed"

    restart_add_planned_requirement \
        reboot \
        system \
        "Kernel changed"

    assert_equal \
        "1" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"
}

test_consolidate_restart_reasons() {
    local temp_dir
    local key
    local reasons

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    restart_add_planned_requirement \
        reboot \
        system \
        "Kernel changed"

    restart_add_planned_requirement \
        reboot \
        system \
        "Firmware changed"

    key="$(restart_requirement_key reboot system)"
    reasons="${LWBS_PLANNED_RESTART_REASONS[$key]}"

    assert_equal \
        "1" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"

    assert_contains "$reasons" "Kernel changed"
    assert_contains "$reasons" "Firmware changed"
}

test_module_restart_only_planned_for_changes() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    LWBS_MODULE_RESTART_REQUIREMENTS=(
        "shell|current-shell|Shell environment changed"
    )

    plan_module_restart_requirements sample

    assert_equal \
        "0" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"

    LWBS_PLAN_MODULE_INSTALL_PACKAGES["sample"]="example-package"

    plan_module_restart_requirements sample

    assert_equal \
        "1" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"
}

test_external_restart_only_planned_for_install() {
    local temp_dir
    local external_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    external_key="$(
        execution_plan_external_key \
            sample \
            sample-external
    )"

    LWBS_EXTERNAL_RESTART_REQUIREMENTS=(
        "application|Example App|New installation requires application restart"
    )

    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="skip"

    plan_external_restart_requirements \
        sample \
        sample-external \
        "$external_key"

    assert_equal \
        "0" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"

    reset_planned_restart_requirements

    LWBS_EXTERNAL_RESTART_REQUIREMENTS=(
        "application|Example App|New installation requires application restart"
    )

    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="install"

    plan_external_restart_requirements \
        sample \
        sample-external \
        "$external_key"

    assert_equal \
        "1" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"
}

test_record_module_restart_after_successful_change() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    LWBS_PLAN_MODULE_RESTART_REQUIREMENTS["sample"]=$'logout|user-session|Group membership changed'

    record_execution_result \
        "package::sample::example" \
        package \
        sample \
        example \
        successful \
        "verified installed"

    record_module_restart_requirements sample

    assert_equal \
        "1" \
        "${#LWBS_RESTART_KEYS[@]}"
}

test_failed_external_action_does_not_record_requirement() {
    local temp_dir
    local installer_dir
    local external_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    installer_dir="$temp_dir/installers"
    mkdir -p -- "$installer_dir"

    cat >"$installer_dir/failing.sh" <<'EOF'
external_id() {
    printf '%s\n' "failing"
}

external_name() {
    printf '%s\n' "Failing"
}

external_description() {
    printf '%s\n' "Failing installer fixture."
}

external_method() {
    printf '%s\n' "script"
}

external_state() {
    printf '%s\n' "absent"
}

external_script_apply() {
    return 1
}

external_restart_requirements() {
    printf '%s\n' \
        "reboot|system|Installer requested a reboot"
}
EOF

    LWBS_EXTERNAL_INSTALLERS_DIR_OVERRIDE="$installer_dir"
    DISTRO_ADAPTER_PROFILE="ubuntu"

    external_key="$(
        execution_plan_external_key \
            sample \
            failing
    )"

    LWBS_PLAN_MODULE_EXTERNALS["sample"]="failing"
    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="install"

    load_external_installer failing

    plan_external_restart_requirements \
        sample \
        failing \
        "$external_key"

    reset_external_installer_contract

    if execute_planned_external_actions sample; then
        printf 'Failing external installer unexpectedly succeeded.\n' >&2
        return 1
    fi

    assert_equal \
        "0" \
        "${#LWBS_RESTART_KEYS[@]}"
}

test_planned_restart_requirements_are_displayed() {
    local temp_dir
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    restart_add_planned_requirement \
        shell \
        current-shell \
        "Shell environment changed"

    output="$(show_planned_restart_requirements)"

    assert_contains \
        "$output" \
        "Potential follow-up requirements"

    assert_contains \
        "$output" \
        "Restart current shell"

    assert_contains \
        "$output" \
        "Shell environment changed"
}

test_recorded_restart_requirements_are_displayed() {
    local temp_dir
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_restart_test "$temp_dir"

    restart_add_recorded_requirement \
        application \
        "Example App" \
        "Application environment changed"

    output="$(show_recorded_restart_requirements)"

    assert_contains \
        "$output" \
        "Follow-up requirements"

    assert_contains \
        "$output" \
        "Restart application: Example App"

    assert_contains \
        "$output" \
        "Application environment changed"
}

run_test \
    "parse a valid restart requirement" \
    test_parse_restart_requirement

run_test \
    "reject an invalid restart target" \
    test_reject_invalid_restart_target

run_test \
    "deduplicate identical restart requirements" \
    test_deduplicate_restart_requirements

run_test \
    "consolidate reasons for the same restart action" \
    test_consolidate_restart_reasons

run_test \
    "plan module restart requirements only when changes are planned" \
    test_module_restart_only_planned_for_changes

run_test \
    "plan external restart requirements only for installation" \
    test_external_restart_only_planned_for_install

run_test \
    "record module restart requirements after successful changes" \
    test_record_module_restart_after_successful_change

run_test \
    "avoid restart requirements for failed external actions" \
    test_failed_external_action_does_not_record_requirement

run_test \
    "show potential restart requirements during planning" \
    test_planned_restart_requirements_are_displayed

run_test \
    "show recorded restart requirements after execution" \
    test_recorded_restart_requirements_are_displayed

finish_tests
