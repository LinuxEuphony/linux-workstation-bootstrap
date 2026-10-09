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

test_supported_distros() {
    is_supported_distro ubuntu
    is_supported_distro debian
    is_supported_distro kali
}

test_future_detectable_distros_not_yet_supported() {
    if is_supported_distro fedora; then
        printf 'Fedora unexpectedly appears as an implemented profile.\n' >&2
        return 1
    fi

    if is_supported_distro arch; then
        printf 'Arch unexpectedly appears as an implemented profile.\n' >&2
        return 1
    fi

    return 0
}

test_command_exists() {
    command_exists bash

    if command_exists "lwbs-command-that-does-not-exist-$$"; then
        printf 'command_exists accepted a nonexistent command.\n' >&2
        return 1
    fi
}

test_require_command_rejects_missing_command() {
    if require_command "lwbs-command-that-does-not-exist-$$" \
        >/dev/null 2>&1; then

        printf 'require_command accepted a nonexistent command.\n' >&2
        return 1
    fi

    return 0
}

test_runtime_accepts_linux() {
    uname() {
        printf '%s\n' "Linux"
    }

    validate_runtime
}

test_runtime_rejects_non_linux() {
    uname() {
        printf '%s\n' "Darwin"
    }

    if validate_runtime >/dev/null 2>&1; then
        printf 'validate_runtime accepted a non-Linux platform.\n' >&2
        return 1
    fi

    return 0
}

run_test \
    "recognize implemented distribution profiles" \
    test_supported_distros

run_test \
    "keep Fedora and Arch detectable but unsupported for installation" \
    test_future_detectable_distros_not_yet_supported

run_test \
    "detect commands in PATH" \
    test_command_exists

run_test \
    "reject missing required commands" \
    test_require_command_rejects_missing_command

run_test \
    "accept Linux runtime" \
    test_runtime_accepts_linux

run_test \
    "reject non-Linux runtime" \
    test_runtime_rejects_non_linux

finish_tests