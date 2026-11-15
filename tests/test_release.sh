#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/version.sh
source "$REPO_ROOT/lib/version.sh"

# shellcheck source=../scripts/release/validate-release.sh
source "$REPO_ROOT/scripts/release/validate-release.sh"

# shellcheck source=../scripts/release/package-release.sh
source "$REPO_ROOT/scripts/release/package-release.sh"

test_accept_release_tag_format() {
    release_validate_tag_format "v1.2.3"
}

test_reject_prerelease_tag_format() {
    if release_validate_tag_format "v1.2.3-dev"; then
        printf 'Prerelease tag was accepted as a published release tag.\n' >&2
        return 1
    fi
}

test_match_release_tag_and_version() {
    release_validate_tag_matches_version \
        "v2.4.6" \
        "2.4.6"
}

test_reject_release_tag_version_mismatch() {
    if release_validate_tag_matches_version \
        "v2.4.6" \
        "2.4.7"; then

        printf 'Mismatched release tag and version were accepted.\n' >&2
        return 1
    fi
}

test_release_archive_contains_only_distribution_files() {
    local temp_dir
    local output_directory
    local archive
    local archive_contents

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    output_directory="$temp_dir/dist"

    release_package "$output_directory" >/dev/null

    archive="$(
        find \
            "$output_directory" \
            -maxdepth 1 \
            -type f \
            -name '*.tar.gz' \
            -print \
            -quit
    )"

    if [[ -z "$archive" ]]; then
        printf 'Release archive was not created.\n' >&2
        return 1
    fi

    archive_contents="$(tar -tzf "$archive")"

    assert_contains \
        "$archive_contents" \
        "/VERSION"

    assert_contains \
        "$archive_contents" \
        "/bin/linux-workstation-bootstrap"

    if [[ "$archive_contents" == *"/tests/"* ||
        "$archive_contents" == *"/.github/"* ||
        "$archive_contents" == *"/.git/"* ]]; then

        printf 'Development-only content leaked into the release archive.\n' \
            >&2

        return 1
    fi

    if [[ ! -f "$archive.sha256" ]]; then
        printf 'Release checksum file was not created.\n' >&2
        return 1
    fi
}

run_test \
    "accept stable release tag format" \
    test_accept_release_tag_format

run_test \
    "reject prerelease Git tags for stable publication" \
    test_reject_prerelease_tag_format

run_test \
    "match release tags to stable versions" \
    test_match_release_tag_and_version

run_test \
    "reject mismatched release tags and versions" \
    test_reject_release_tag_version_mismatch

run_test \
    "package only distribution files for release" \
    test_release_archive_contains_only_distribution_files

finish_tests
