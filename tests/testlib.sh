#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Minimal test harness used by the repository test suite.
#
# The harness intentionally depends only on Bash so the core test suite can
# run locally and in CI without installing a separate testing framework.

LWBS_TEST_COUNT=0
LWBS_TEST_FAILURE_COUNT=0

# Execute one test function in an isolated subshell.
run_test() {
    local test_name="${1:-}"
    local test_function="${2:-}"

    if [[ -z "$test_name" || -z "$test_function" ]]; then
        printf 'Error: run_test requires a name and test function.\n' >&2
        return 2
    fi

    ((LWBS_TEST_COUNT += 1))

    printf 'TEST: %s\n' "$test_name"

    if (
        set -Eeuo pipefail
        "$test_function"
    ); then
        printf 'PASS: %s\n\n' "$test_name"
        return 0
    fi

    ((LWBS_TEST_FAILURE_COUNT += 1))

    printf 'FAIL: %s\n\n' "$test_name"

    return 0
}

# Assert that two values are exactly equal.
assert_equal() {
    local expected="${1-}"
    local actual="${2-}"
    local message="${3:-values are not equal}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    fi

    printf 'Assertion failed: %s\n' "$message" >&2
    printf '  Expected: %q\n' "$expected" >&2
    printf '  Actual  : %q\n' "$actual" >&2

    return 1
}

# Assert that one string contains another string.
assert_contains() {
    local haystack="${1-}"
    local needle="${2-}"
    local message="${3:-expected text was not found}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    fi

    printf 'Assertion failed: %s\n' "$message" >&2
    printf '  Expected to contain: %q\n' "$needle" >&2
    printf '  Actual             : %q\n' "$haystack" >&2

    return 1
}

# Assert that a filesystem path does not exist.
assert_not_exists() {
    local path="${1:-}"
    local message="${2:-path unexpectedly exists}"

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    printf 'Assertion failed: %s\n' "$message" >&2
    printf '  Path: %s\n' "$path" >&2

    return 1
}

# Create an isolated temporary directory for one test.
make_test_temp_dir() {
    mktemp -d "${TMPDIR:-/tmp}/lwbs-test.XXXXXX"
}

# Register one temporary path for removal when the isolated test exits.
#
# The path is shell-escaped when the trap is registered so cleanup does not
# depend on a local variable that may no longer exist when the EXIT trap runs.
register_test_cleanup() {
    local path="${1:-}"
    local escaped_path

    if [[ -z "$path" ]]; then
        printf 'Error: register_test_cleanup requires a path.\n' >&2
        return 2
    fi

    printf -v escaped_path '%q' "$path"

    trap "rm -rf -- $escaped_path" EXIT
}

# Initialize logging beneath an isolated test directory.
setup_test_logging() {
    local test_directory="${1:-}"

    if [[ -z "$test_directory" ]]; then
        printf 'Error: setup_test_logging requires a test directory.\n' >&2
        return 2
    fi

    export XDG_STATE_HOME="$test_directory/state"
    export HOME="$test_directory/home"

    mkdir -p -- "$HOME"

    init_logging
}

# Print the result for the current test file.
finish_tests() {
    local passed_count

    passed_count=$((LWBS_TEST_COUNT - LWBS_TEST_FAILURE_COUNT))

    printf 'Tests: %d | Passed: %d | Failed: %d\n' \
        "$LWBS_TEST_COUNT" \
        "$passed_count" \
        "$LWBS_TEST_FAILURE_COUNT"

    if ((LWBS_TEST_FAILURE_COUNT > 0)); then
        return 1
    fi

    return 0
}