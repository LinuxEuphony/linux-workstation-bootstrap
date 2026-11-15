#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# External artifact integrity verification tests.
#
# Validates:
# 1. SHA-256 integrity declaration parsing.
# 2. Invalid checksum metadata rejection.
# 3. Successful checksum verification.
# 4. Checksum mismatch rejection.
# 5. Trusted signature declaration parsing.
# 6. Duplicate artifact declaration rejection.
# 7. Dry-run verification planning.
# 8. Mandatory verification metadata for downloads.
# 9. Rejection of unverified downloaded artifacts.
# 10. Integrity visibility in the execution plan.
#
# Tests use controlled local fixtures and do not download remote artifacts or
# modify the workstation.
#
# shellcheck disable=SC2317,SC2329

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

TEST_INTEGRITY_REQUIREMENTS=""

external_integrity_requirements() {
    printf '%s\n' "$TEST_INTEGRITY_REQUIREMENTS"
}

prepare_integrity_test() {
    local temp_dir="${1:-}"

    setup_test_logging "$temp_dir"

    reset_external_integrity_state
    reset_execution_plan
    reset_restart_tracking

    LWBS_EXTERNAL_ID="integrity-fixture"
    LWBS_EXTERNAL_STAGE_DIR="$temp_dir/stage"

    LWBS_DRY_RUN=false
    LWBS_ASSUME_YES=false

    TEST_INTEGRITY_REQUIREMENTS=""

    mkdir -p -- "$LWBS_EXTERNAL_STAGE_DIR"
}

test_load_sha256_requirement() {
    local temp_dir
    local checksum

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    checksum="$(printf 'a%.0s' {1..64})"

    TEST_INTEGRITY_REQUIREMENTS="fixture|sha256|$checksum"

    load_external_integrity_requirements

    assert_equal \
        "1" \
        "${#LWBS_EXTERNAL_INTEGRITY_IDS[@]}"

    assert_equal \
        "fixture" \
        "${LWBS_EXTERNAL_INTEGRITY_IDS[0]}"

    assert_equal \
        "sha256" \
        "${LWBS_EXTERNAL_INTEGRITY_METHODS[fixture]}"

    assert_equal \
        "$checksum" \
        "${LWBS_EXTERNAL_INTEGRITY_SHA256[fixture]}"
}

test_reject_invalid_sha256_requirement() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    TEST_INTEGRITY_REQUIREMENTS="fixture|sha256|invalid"

    if load_external_integrity_requirements >/dev/null 2>&1; then
        printf 'Invalid SHA-256 metadata was accepted.\n' >&2
        return 1
    fi
}

test_verify_matching_sha256() {
    local temp_dir
    local artifact
    local checksum_output
    local checksum

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    artifact="$temp_dir/fixture.bin"

    printf '%s' \
        "linux-workstation-bootstrap integrity fixture" \
        >"$artifact"

    checksum_output="$(sha256sum -- "$artifact")"
    checksum="${checksum_output%% *}"

    TEST_INTEGRITY_REQUIREMENTS="fixture|sha256|$checksum"

    load_external_integrity_requirements

    integrity_verify_artifact \
        fixture \
        "$artifact"

    assert_equal \
        "verified:fixture" \
        "${LWBS_EXTERNAL_VERIFIED_PATHS[$artifact]}"
}

test_reject_sha256_mismatch() {
    local temp_dir
    local artifact
    local checksum

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    artifact="$temp_dir/fixture.bin"

    printf '%s' \
        "unexpected artifact contents" \
        >"$artifact"

    checksum="$(printf '0%.0s' {1..64})"

    TEST_INTEGRITY_REQUIREMENTS="fixture|sha256|$checksum"

    load_external_integrity_requirements

    if integrity_verify_artifact \
        fixture \
        "$artifact" \
        >/dev/null 2>&1; then

        printf 'SHA-256 mismatch was accepted.\n' >&2
        return 1
    fi

    if [[ -n "${LWBS_EXTERNAL_VERIFIED_PATHS[$artifact]:-}" ]]; then
        printf 'Failed artifact was incorrectly marked as verified.\n' >&2
        return 1
    fi
}

test_load_signature_requirement() {
    local temp_dir
    local keyring
    local fingerprint

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    keyring="$temp_dir/vendor.gpg"
    fingerprint="$(printf 'A%.0s' {1..40})"

    touch "$keyring"

    TEST_INTEGRITY_REQUIREMENTS="fixture|signature|$keyring|$fingerprint"

    load_external_integrity_requirements

    assert_equal \
        "1" \
        "${#LWBS_EXTERNAL_INTEGRITY_IDS[@]}"

    assert_equal \
        "signature" \
        "${LWBS_EXTERNAL_INTEGRITY_METHODS[fixture]}"

    assert_equal \
        "$keyring" \
        "${LWBS_EXTERNAL_INTEGRITY_KEYRINGS[fixture]}"

    assert_equal \
        "$fingerprint" \
        "${LWBS_EXTERNAL_INTEGRITY_FINGERPRINTS[fixture]}"
}

test_reject_duplicate_artifact_requirements() {
    local temp_dir
    local checksum

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    checksum="$(printf 'a%.0s' {1..64})"

    TEST_INTEGRITY_REQUIREMENTS="$(
        printf '%s\n' \
            "fixture|sha256|$checksum" \
            "fixture|sha256|$checksum"
    )"

    if load_external_integrity_requirements >/dev/null 2>&1; then
        printf 'Duplicate artifact integrity metadata was accepted.\n' >&2
        return 1
    fi
}

test_dry_run_download_records_planned_verification() {
    local temp_dir
    local destination
    local checksum

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    destination="$LWBS_EXTERNAL_STAGE_DIR/fixture.bin"
    checksum="$(printf 'a%.0s' {1..64})"

    TEST_INTEGRITY_REQUIREMENTS="fixture|sha256|$checksum"

    load_external_integrity_requirements

    LWBS_DRY_RUN=true

    external_download \
        fixture \
        "https://example.com/fixture.bin" \
        "$destination"

    assert_equal \
        "fixture" \
        "${LWBS_EXTERNAL_DOWNLOADED_PATHS[$destination]}"

    assert_equal \
        "planned:fixture" \
        "${LWBS_EXTERNAL_VERIFIED_PATHS[$destination]}"

    if [[ -e "$destination" ]]; then
        printf 'Dry-run unexpectedly created the external artifact.\n' >&2
        return 1
    fi
}

test_download_requires_integrity_metadata() {
    local temp_dir
    local destination

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    destination="$LWBS_EXTERNAL_STAGE_DIR/fixture.bin"

    LWBS_DRY_RUN=true

    if external_download \
        fixture \
        "https://example.com/fixture.bin" \
        "$destination" \
        >/dev/null 2>&1; then

        printf 'External download without integrity metadata was accepted.\n' \
            >&2

        return 1
    fi
}

test_unverified_download_is_rejected() {
    local temp_dir
    local artifact

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    artifact="$LWBS_EXTERNAL_STAGE_DIR/fixture.bin"

    touch "$artifact"

    integrity_mark_downloaded \
        fixture \
        "$artifact"

    if integrity_require_verified_if_downloaded \
        "$artifact" \
        >/dev/null 2>&1; then

        printf 'Downloaded artifact without verification was accepted.\n' >&2
        return 1
    fi
}

test_execution_plan_displays_integrity_requirement() {
    local temp_dir
    local external_key
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_integrity_test "$temp_dir"

    LWBS_PLAN_STATUS="resolved"

    LWBS_PLAN_PROFILE_ID="integrity-profile"
    LWBS_PLAN_PROFILE_NAME="Integrity Profile"
    LWBS_PLAN_PROFILE_DESCRIPTION="Integrity planning fixture."
    LWBS_PLAN_DISTRO_PROFILE="ubuntu"

    LWBS_TARGET_USER="developer"

    LWBS_PLAN_MODULES=(
        "integrity-module"
    )

    LWBS_PLAN_MODULE_NAMES["integrity-module"]="Integrity Module"
    LWBS_PLAN_MODULE_EXTERNALS["integrity-module"]="integrity-fixture"

    external_key="$(
        execution_plan_external_key \
            integrity-module \
            integrity-fixture
    )"

    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="install"
    LWBS_PLAN_EXTERNAL_VERIFICATIONS["$external_key"]="fixture|sha256"

    output="$(show_execution_plan)"

    assert_contains \
        "$output" \
        "External      : integrity-fixture [install]"

    assert_contains \
        "$output" \
        "Verification  : fixture [sha256]"
}

run_test \
    "load SHA-256 integrity metadata" \
    test_load_sha256_requirement

run_test \
    "reject invalid SHA-256 integrity metadata" \
    test_reject_invalid_sha256_requirement

run_test \
    "verify a matching SHA-256 checksum" \
    test_verify_matching_sha256

run_test \
    "reject a SHA-256 mismatch" \
    test_reject_sha256_mismatch

run_test \
    "load trusted signature integrity metadata" \
    test_load_signature_requirement

run_test \
    "reject duplicate integrity declarations for an artifact" \
    test_reject_duplicate_artifact_requirements

run_test \
    "record planned verification during dry-run without downloading" \
    test_dry_run_download_records_planned_verification

run_test \
    "reject external downloads without integrity metadata" \
    test_download_requires_integrity_metadata

run_test \
    "reject downloaded artifacts that were not verified" \
    test_unverified_download_is_rejected

run_test \
    "show integrity verification in the execution plan" \
    test_execution_plan_displays_integrity_requirement

finish_tests
