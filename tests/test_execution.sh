#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../config/defaults.sh
source "$REPO_ROOT/config/defaults.sh"

# shellcheck source=../lib/core.sh
source "$REPO_ROOT/lib/core.sh"

# shellcheck source=../lib/logging.sh
source "$REPO_ROOT/lib/logging.sh"

# shellcheck source=../lib/execution.sh
source "$REPO_ROOT/lib/execution.sh"

test_dry_run_does_not_execute_command() {
    local temp_dir
    local marker
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    marker="$temp_dir/marker"

    LWBS_DRY_RUN=true

    output="$(run_command touch "$marker")"

    assert_not_exists \
        "$marker" \
        "dry-run executed a system command"

    assert_contains \
        "$output" \
        "[DRY-RUN] Would execute: touch"
}

test_command_exit_code_is_preserved() {
    local temp_dir
    local exit_code

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_DRY_RUN=false

    controlled_failure() {
        return 7
    }

    if run_command controlled_failure; then
        printf 'Failing command unexpectedly succeeded.\n' >&2
        return 1
    else
        exit_code=$?
    fi

    assert_equal "7" "$exit_code"
}

test_privileged_dry_run_performs_no_change() {
    local temp_dir
    local marker
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    marker="$temp_dir/privileged-marker"

    LWBS_DRY_RUN=true

    output="$(
        run_privileged_command \
            touch \
            "$marker"
    )"

    assert_not_exists \
        "$marker" \
        "privileged dry-run modified the host"

    assert_contains \
        "$output" \
        "[DRY-RUN] Would execute with root privileges: touch"
}

test_execution_requires_command() {
    local temp_dir
    local exit_code

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_DRY_RUN=false

    if run_command >/dev/null 2>&1; then
        printf 'run_command accepted an empty command.\n' >&2
        return 1
    else
        exit_code=$?
    fi

    assert_equal "2" "$exit_code"
}

run_test \
    "dry-run skips normal command execution" \
    test_dry_run_does_not_execute_command

run_test \
    "preserve command failure exit codes" \
    test_command_exit_code_is_preserved

run_test \
    "dry-run skips privileged command execution" \
    test_privileged_dry_run_performs_no_change

run_test \
    "reject empty command execution requests" \
    test_execution_requires_command

finish_tests