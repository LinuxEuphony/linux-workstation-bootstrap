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

# shellcheck source=../lib/distro.sh
source "$REPO_ROOT/lib/distro.sh"

test_load_supported_adapters() {
    local temp_dir
    local profile

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    for profile in ubuntu debian kali; do
        LWBS_ROOT="$REPO_ROOT"

        load_distro_adapter "$profile"

        assert_equal \
            "$profile" \
            "$DISTRO_ADAPTER_PROFILE"

        reset_distro_adapter_contract
    done
}

test_reject_unsupported_adapter() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_ROOT="$REPO_ROOT"

    if load_distro_adapter fedora >/dev/null 2>&1; then
        printf 'Unsupported Fedora adapter was accepted.\n' >&2
        return 1
    fi

    return 0
}

test_missing_adapter_fails() {
    local temp_dir
    local fake_root

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    fake_root="$temp_dir/repository"

    mkdir -p -- "$fake_root/distros"

    LWBS_ROOT="$fake_root"

    if load_distro_adapter ubuntu >/dev/null 2>&1; then
        printf 'Missing Ubuntu adapter was accepted.\n' >&2
        return 1
    fi

    return 0
}

test_incomplete_adapter_fails_contract_validation() {
    local temp_dir
    local fake_root

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    fake_root="$temp_dir/repository"

    mkdir -p -- "$fake_root/distros"

    cat >"$fake_root/distros/ubuntu.sh" <<'EOF'
distro_validate_environment() {
    return 0
}
EOF

    LWBS_ROOT="$fake_root"

    if load_distro_adapter ubuntu >/dev/null 2>&1; then
        printf 'Incomplete distro adapter was accepted.\n' >&2
        return 1
    fi

    return 0
}

test_adapter_environment_validation_without_host_changes() {
    local temp_dir
    local profile

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    require_command() {
        return 0
    }

    SYSTEM_DISTRO_FAMILY="debian"
    SYSTEM_PACKAGE_MANAGER="apt"

    for profile in ubuntu debian kali; do
        LWBS_ROOT="$REPO_ROOT"

        load_distro_adapter "$profile"
        distro_validate_environment

        reset_distro_adapter_contract
    done
}

test_adapter_rejects_incompatible_family() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    require_command() {
        return 0
    }

    SYSTEM_DISTRO_FAMILY="rpm"
    SYSTEM_PACKAGE_MANAGER="dnf"

    LWBS_ROOT="$REPO_ROOT"

    load_distro_adapter ubuntu

    if distro_validate_environment >/dev/null 2>&1; then
        printf 'Ubuntu adapter accepted an RPM-family environment.\n' >&2
        return 1
    fi

    return 0
}

test_adapter_package_install_is_safe_in_dry_run() {
    local temp_dir
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_ROOT="$REPO_ROOT"
    LWBS_DRY_RUN=true

    load_distro_adapter ubuntu

    output="$(
        distro_install_packages \
            lwbs-example-package
    )"

    assert_contains \
        "$output" \
        "[DRY-RUN] Would execute with root privileges: apt-get"
}

test_local_package_install_is_safe_in_dry_run() {
    local temp_dir
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_ROOT="$REPO_ROOT"
    LWBS_DRY_RUN=true

    load_distro_adapter ubuntu

    output="$(
        distro_install_local_package \
            "/tmp/lwbs-example-package.deb"
    )"

    assert_contains \
        "$output" \
        "[DRY-RUN] Would execute with root privileges: apt-get"
}

run_test \
    "load every currently supported distro adapter" \
    test_load_supported_adapters

run_test \
    "reject distro profiles without implemented adapters" \
    test_reject_unsupported_adapter

run_test \
    "fail clearly when an adapter file is missing" \
    test_missing_adapter_fails

run_test \
    "reject incomplete distro adapter contracts" \
    test_incomplete_adapter_fails_contract_validation

run_test \
    "validate Debian-family adapters without modifying the host" \
    test_adapter_environment_validation_without_host_changes

run_test \
    "reject an incompatible distro family" \
    test_adapter_rejects_incompatible_family

run_test \
    "keep repository package installation safe in dry-run" \
    test_adapter_package_install_is_safe_in_dry_run

run_test \
    "keep local package installation safe in dry-run" \
    test_local_package_install_is_safe_in_dry_run

finish_tests