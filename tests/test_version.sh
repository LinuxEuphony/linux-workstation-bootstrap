#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

test_accept_stable_semver() {
    version_is_semver "1.2.3"
}

test_accept_development_semver() {
    version_is_semver "1.2.3-dev"
}

test_reject_invalid_version() {
    if version_is_semver "version-one"; then
        printf 'Invalid Semantic Version was accepted.\n' >&2
        return 1
    fi
}

test_load_version_from_single_source() {
    local temp_dir
    local version_file

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    version_file="$temp_dir/VERSION"

    printf '%s\n' "2.3.4-dev" >"$version_file"

    load_project_version "$version_file"

    assert_equal \
        "2.3.4-dev" \
        "$LWBS_VERSION"

    assert_equal \
        "$version_file" \
        "$LWBS_VERSION_FILE"
}

test_reject_multiline_version_file() {
    local temp_dir
    local version_file

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    version_file="$temp_dir/VERSION"

    printf '%s\n' \
        "1.0.0" \
        "unexpected" >"$version_file"

    if load_project_version \
        "$version_file" \
        >/dev/null 2>&1; then

        printf 'Multiline VERSION file was accepted.\n' >&2
        return 1
    fi
}

test_match_release_tag_to_version() {
    version_tag_matches \
        "v1.2.3" \
        "1.2.3"
}

test_version_output_uses_loaded_version() {
    local temp_dir
    local version_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    version_file="$temp_dir/VERSION"

    printf '%s\n' "4.5.6-dev" >"$version_file"

    load_project_version "$version_file"

    output="$(show_version)"

    assert_contains \
        "$output" \
        "4.5.6-dev"
}

run_test \
    "accept a stable Semantic Version" \
    test_accept_stable_semver

run_test \
    "accept a development Semantic Version" \
    test_accept_development_semver

run_test \
    "reject an invalid project version" \
    test_reject_invalid_version

run_test \
    "load the application version from VERSION" \
    test_load_version_from_single_source

run_test \
    "reject a multiline VERSION file" \
    test_reject_multiline_version_file

run_test \
    "match release tags to project versions" \
    test_match_release_tag_to_version

run_test \
    "report the loaded version through --version output" \
    test_version_output_uses_loaded_version

finish_tests
