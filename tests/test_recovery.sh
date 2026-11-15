#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

prepare_recovery_test() {
    local temp_dir="${1:-}"

    setup_test_logging "$temp_dir"

    reset_recovery_runtime_state
    reset_execution_results

    initialize_recovery_state
}

test_begin_run_creates_active_state() {
    local temp_dir
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run developer ubuntu

    if [[ ! -f "$LWBS_RECOVERY_ACTIVE_FILE" ]]; then
        printf 'Recovery active state was not created.\n' >&2
        return 1
    fi

    recovery_read_state_file \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        state

    assert_equal \
        "executing" \
        "${state[status]}"

    assert_equal \
        "developer" \
        "${state[profile]}"

    assert_equal \
        "ubuntu" \
        "${state[distro]}"
}

test_successful_action_updates_checkpoint() {
    local temp_dir
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run developer ubuntu

    recovery_record_successful_action \
        package \
        development-tools \
        git

    recovery_read_state_file \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        state

    assert_equal \
        "package" \
        "${state[last_success_type]}"

    assert_equal \
        "development-tools" \
        "${state[last_success_module]}"

    assert_equal \
        "git" \
        "${state[last_success_target]}"
}

test_completed_run_finalizes_transient_state() {
    local temp_dir
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run default ubuntu
    recovery_finalize_run completed

    assert_not_exists \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        "completed run left active recovery state"

    recovery_read_state_file \
        "$LWBS_RECOVERY_LAST_FILE" \
        state

    assert_equal \
        "completed" \
        "${state[status]}"
}

test_failed_run_is_distinct_from_interrupted_run() {
    local temp_dir
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run default ubuntu
    recovery_finalize_run failed

    recovery_read_state_file \
        "$LWBS_RECOVERY_LAST_FILE" \
        state

    assert_equal \
        "failed" \
        "${state[status]}"

    assert_equal \
        "false" \
        "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED"
}

test_stale_executing_run_is_detected_as_interrupted() {
    local temp_dir
    local previous_run_id
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run developer ubuntu

    previous_run_id="$LWBS_RECOVERY_CURRENT_RUN_ID"

    reset_recovery_runtime_state

    recovery_detect_previous_run >/dev/null

    assert_equal \
        "true" \
        "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED"

    assert_equal \
        "$previous_run_id" \
        "$LWBS_RECOVERY_PREVIOUS_RUN_ID"

    assert_not_exists \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        "interrupted run remained active after detection"

    recovery_read_state_file \
        "$LWBS_RECOVERY_LAST_FILE" \
        state

    assert_equal \
        "interrupted" \
        "${state[status]}"
}

test_completed_active_state_is_cleaned_without_interruption_warning() {
    local temp_dir
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run default ubuntu

    recovery_read_state_file \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        state

    state["status"]="completed"
    state["updated_at"]="$(recovery_timestamp)"

    recovery_write_state_map \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        state

    reset_recovery_runtime_state

    recovery_detect_previous_run

    assert_equal \
        "false" \
        "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED"

    assert_not_exists \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        "completed active recovery state was not cleaned"
}

test_execution_result_updates_recovery_checkpoint() {
    local temp_dir
    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run developer ubuntu

    record_execution_result \
        "package::development-tools::git" \
        package \
        development-tools \
        git \
        successful \
        "verified installed"

    recovery_read_state_file \
        "$LWBS_RECOVERY_ACTIVE_FILE" \
        state

    assert_equal \
        "git" \
        "${state[last_success_target]}"
}

test_recovery_metadata_does_not_store_result_details() {
    local temp_dir
    local secret_value
    local recovery_contents

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    recovery_begin_run developer ubuntu

    secret_value="token-super-secret-value"

    record_execution_result \
        "package::development-tools::git" \
        package \
        development-tools \
        git \
        successful \
        "$secret_value"

    recovery_contents="$(cat "$LWBS_RECOVERY_ACTIVE_FILE")"

    if [[ "$recovery_contents" == *"$secret_value"* ]]; then
        printf 'Sensitive result details leaked into recovery metadata.\n' >&2
        return 1
    fi
}

test_recovery_plan_notice_explains_fresh_planning() {
    local temp_dir
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_recovery_test "$temp_dir"

    LWBS_RECOVERY_PREVIOUS_INTERRUPTED=true
    LWBS_RECOVERY_PREVIOUS_RUN_ID="previous-run"

    output="$(show_recovery_plan_notice)"

    assert_contains \
        "$output" \
        "plan rebuilt from current state"
}

run_test \
    "create active recovery state when execution begins" \
    test_begin_run_creates_active_state

run_test \
    "record the last successfully completed action" \
    test_successful_action_updates_checkpoint

run_test \
    "finalize successful runs and remove transient state" \
    test_completed_run_finalizes_transient_state

run_test \
    "distinguish normal execution failure from interruption" \
    test_failed_run_is_distinct_from_interrupted_run

run_test \
    "detect stale executing runs as interrupted" \
    test_stale_executing_run_is_detected_as_interrupted

run_test \
    "clean completed transient state without reporting interruption" \
    test_completed_active_state_is_cleaned_without_interruption_warning

run_test \
    "update recovery checkpoints from verified execution results" \
    test_execution_result_updates_recovery_checkpoint

run_test \
    "keep execution result details out of recovery metadata" \
    test_recovery_metadata_does_not_store_result_details

run_test \
    "explain fresh planning after an interrupted run" \
    test_recovery_plan_notice_explains_fresh_planning

finish_tests
