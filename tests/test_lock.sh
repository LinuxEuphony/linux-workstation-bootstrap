#!/usr/bin/env bash

# shellcheck disable=SC2153

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

prepare_lock_test() {
    local temp_dir="${1:-}"

    export XDG_STATE_HOME="$temp_dir/state"
    export HOME="$temp_dir/home"

    mkdir -p -- "$HOME"

    LWBS_STATE_DIR=""
    LWBS_LOG_DIR=""
    LWBS_LOG_FILE=""

    reset_execution_lock_state
    reset_recovery_runtime_state

    initialize_application_state
    initialize_execution_lock
}

test_acquire_lock_creates_owner_metadata() {
    local temp_dir

    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_lock_test "$temp_dir"

    acquire_execution_lock

    if [[ ! -d "$LWBS_LOCK_DIR" ]]; then
        printf 'Execution lock directory was not created.\n' >&2
        return 1
    fi

    if [[ ! -f "$LWBS_LOCK_METADATA_FILE" ]]; then
        printf 'Execution lock metadata was not created.\n' >&2
        return 1
    fi

    lock_read_metadata state

    assert_equal \
        "$BASHPID" \
        "${state[pid]}"

    release_execution_lock
}

test_reject_active_concurrent_owner() {
    local temp_dir
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_lock_test "$temp_dir"

    acquire_execution_lock

    if output="$(
        (
            LWBS_LOCK_ACQUIRED=false
            LWBS_LOCK_OWNER_PID=""
            LWBS_LOCK_OWNER_START_TICKS=""

            acquire_execution_lock
        ) 2>&1
    )"; then

        printf 'Concurrent lock acquisition unexpectedly succeeded.\n' >&2
        return 1
    fi

    assert_contains \
        "$output" \
        "another Linux Workstation Bootstrap process is already running"

    release_execution_lock
}

test_replace_stale_lock() {
    local temp_dir
    local stale_pid

    local -A state=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_lock_test "$temp_dir"

    stale_pid="$BASHPID"

    mkdir -p -- "$LWBS_LOCK_DIR"

    # Use the current PID with an impossible start time. This models PID reuse
    # deterministically without relying on an arbitrary process ID being free.
    lock_write_metadata \
        "$stale_pid" \
        0 \
        "2026-01-01T00:00:00+0000"

    acquire_execution_lock

    lock_read_metadata state

    assert_equal \
        "$BASHPID" \
        "${state[pid]}"

    if [[ "${state[start_ticks]}" == "0" ]]; then
        printf 'Stale process identity was not replaced.\n' >&2
        return 1
    fi

    release_execution_lock
}

test_release_owned_lock() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_lock_test "$temp_dir"

    acquire_execution_lock
    release_execution_lock

    assert_not_exists \
        "$LWBS_LOCK_DIR" \
        "owned execution lock remained after release"
}

test_do_not_release_foreign_lock() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_lock_test "$temp_dir"

    acquire_execution_lock

    lock_write_metadata \
        "$BASHPID" \
        0 \
        "2026-01-01T00:00:00+0000"

    if release_execution_lock >/dev/null 2>&1; then
        printf 'Foreign lock was incorrectly released.\n' >&2
        return 1
    fi

    if [[ ! -d "$LWBS_LOCK_DIR" ]]; then
        printf 'Foreign lock directory was removed.\n' >&2
        return 1
    fi

    rm -rf -- "$LWBS_LOCK_DIR"
    LWBS_LOCK_ACQUIRED=false
}

test_help_does_not_create_lock() {
    local temp_dir
    local expected_lock

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    export XDG_STATE_HOME="$temp_dir/state"
    export HOME="$temp_dir/home"

    mkdir -p -- "$HOME"

    expected_lock="$XDG_STATE_HOME/$LWBS_APP_SLUG/$LWBS_LOCK_DIRECTORY_NAME"

    bootstrap_main --help >/dev/null

    assert_not_exists \
        "$expected_lock" \
        "help unexpectedly created an execution lock"
}

test_version_does_not_create_lock() {
    local temp_dir
    local expected_lock

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    export XDG_STATE_HOME="$temp_dir/state"
    export HOME="$temp_dir/home"

    mkdir -p -- "$HOME"

    expected_lock="$XDG_STATE_HOME/$LWBS_APP_SLUG/$LWBS_LOCK_DIRECTORY_NAME"

    bootstrap_main --version >/dev/null

    assert_not_exists \
        "$expected_lock" \
        "version unexpectedly created an execution lock"
}

test_stale_lock_allows_interrupted_run_detection() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_lock_test "$temp_dir"

    init_logging

    recovery_begin_run \
        default \
        ubuntu

    reset_recovery_runtime_state

    mkdir -p -- "$LWBS_LOCK_DIR"

    lock_write_metadata \
        "$BASHPID" \
        0 \
        "2026-01-01T00:00:00+0000"

    acquire_execution_lock

    recovery_detect_previous_run >/dev/null

    assert_equal \
        "true" \
        "$LWBS_RECOVERY_PREVIOUS_INTERRUPTED"

    release_execution_lock
}

run_test \
    "create owner metadata when acquiring the execution lock" \
    test_acquire_lock_creates_owner_metadata

run_test \
    "reject a second process while the lock owner is active" \
    test_reject_active_concurrent_owner

run_test \
    "replace a stale execution lock safely" \
    test_replace_stale_lock

run_test \
    "release a lock owned by the current process" \
    test_release_owned_lock

run_test \
    "avoid removing a lock owned by another process" \
    test_do_not_release_foreign_lock

run_test \
    "avoid execution locking for help" \
    test_help_does_not_create_lock

run_test \
    "avoid execution locking for version output" \
    test_version_does_not_create_lock

run_test \
    "integrate stale lock cleanup with interrupted run detection" \
    test_stale_lock_allows_interrupted_run_detection

finish_tests