#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

# shellcheck source=../lib/arguments.sh
source "$REPO_ROOT/lib/arguments.sh"

test_parse_dry_run_and_yes() {
    parse_arguments --dry-run --yes

    assert_equal "true" "$LWBS_DRY_RUN"
    assert_equal "true" "$LWBS_ASSUME_YES"
    assert_equal "run" "$LWBS_CLI_ACTION"
}

test_parse_separate_distro_argument() {
    parse_arguments --distro Debian

    assert_equal "debian" "$LWBS_REQUESTED_DISTRO_PROFILE"
}

test_parse_equals_distro_argument() {
    parse_arguments --distro=Ubuntu

    assert_equal "ubuntu" "$LWBS_REQUESTED_DISTRO_PROFILE"
}

test_parse_help() {
    parse_arguments --help

    assert_equal "help" "$LWBS_CLI_ACTION"
}

test_parse_version() {
    parse_arguments --version

    assert_equal "version" "$LWBS_CLI_ACTION"
}

test_missing_distro_value_fails() {
    local exit_code

    if parse_arguments --distro >/dev/null 2>&1; then
        printf 'Missing --distro value was accepted.\n' >&2
        return 1
    else
        exit_code=$?
    fi

    assert_equal "2" "$exit_code"
}

test_unknown_option_fails() {
    local exit_code

    if parse_arguments --definitely-not-valid >/dev/null 2>&1; then
        printf 'Unknown option was accepted.\n' >&2
        return 1
    else
        exit_code=$?
    fi

    assert_equal "2" "$exit_code"
}

test_positional_argument_fails() {
    local exit_code

    if parse_arguments unexpected >/dev/null 2>&1; then
        printf 'Unexpected positional argument was accepted.\n' >&2
        return 1
    else
        exit_code=$?
    fi

    assert_equal "2" "$exit_code"
}

run_test \
    "parse dry-run and non-interactive approval options" \
    test_parse_dry_run_and_yes

run_test \
    "parse --distro with a separate value" \
    test_parse_separate_distro_argument

run_test \
    "parse --distro=value" \
    test_parse_equals_distro_argument

run_test \
    "parse help action" \
    test_parse_help

run_test \
    "parse version action" \
    test_parse_version

run_test \
    "reject missing --distro value" \
    test_missing_distro_value_fails

run_test \
    "reject unknown CLI option" \
    test_unknown_option_fails

run_test \
    "reject positional arguments" \
    test_positional_argument_fails

finish_tests