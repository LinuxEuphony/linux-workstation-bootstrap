#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

declare -a TEST_FILES=(
    "$TEST_DIR/test_core.sh"
    "$TEST_DIR/test_detection.sh"
    "$TEST_DIR/test_arguments.sh"
    "$TEST_DIR/test_config.sh"
    "$TEST_DIR/test_execution.sh"
    "$TEST_DIR/test_distro.sh"
)

failed_files=0

printf 'Linux Workstation Bootstrap test suite\n'
printf 'Repository: %s\n\n' "$REPO_ROOT"

for test_file in "${TEST_FILES[@]}"; do
    printf '========================================\n'
    printf 'Running %s\n' "$(basename -- "$test_file")"
    printf '========================================\n\n'

    if bash "$test_file"; then
        :
    else
        ((failed_files += 1))
    fi

    printf '\n'
done

printf '========================================\n'

if ((failed_files > 0)); then
    printf 'Test suite failed: %d test file(s) failed.\n' \
        "$failed_files"

    exit 1
fi

printf 'Test suite passed.\n'