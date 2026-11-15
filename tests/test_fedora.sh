#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Fedora distribution integration tests.
#
# Validates Fedora support across:
# 1. Supported distribution configuration.
# 2. RPM package-state detection.
# 3. Fedora capability mappings.
# 4. Unsupported capability handling.
# 5. Developer workstation planning.
# 6. Security workstation planning.
#
# All package, account, and service state used by planning tests is controlled
# locally. These tests do not install packages or modify the workstation.

# shellcheck disable=SC2317,SC2329

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

test_fedora_supported_distribution_contract() {
    is_supported_distro fedora

    assert_equal \
        "Fedora Linux" \
        "${LWBS_DISTRO_DISPLAY_NAMES[fedora]}"

    assert_equal \
        "amd64 arm64" \
        "${LWBS_DISTRO_SUPPORTED_ARCHITECTURES[fedora]}"

    assert_equal \
        "rpm" \
        "${LWBS_DISTRO_FAMILIES[fedora]}"

    assert_equal \
        "dnf" \
        "${LWBS_FAMILY_PACKAGE_MANAGERS[rpm]}"
}

test_fedora_package_state_detection() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_distro_adapter fedora

    rpm() {
        local package="${*: -1}"

        case "$package" in
            lwbs-installed-package)
                return 0
                ;;

            lwbs-absent-package)
                return 1
                ;;

            *)
                return 2
                ;;
        esac
    }

    assert_equal \
        "installed" \
        "$(distro_package_state lwbs-installed-package)"

    assert_equal \
        "absent" \
        "$(distro_package_state lwbs-absent-package)"

    if distro_package_state \
        lwbs-query-error-package \
        >/dev/null 2>&1; then

        printf 'Fedora package-state failure was treated as package absence.\n' \
            >&2

        return 1
    fi

    unset -f rpm

    reset_distro_adapter_contract
}

test_fedora_capability_mapping() {
    local temp_dir
    local capability

    local -a capabilities=(
        "bison"
        "bluetooth-stack"
        "build-toolchain"
        "calibre"
        "cloc"
        "cmake"
        "curl"
        "darktable"
        "docker-engine"
        "dos2unix"
        "ffmpeg"
        "figlet"
        "fingerprint-tools"
        "flex"
        "gimp"
        "git"
        "host-intrusion-protection"
        "inkscape"
        "nano"
        "pavucontrol"
        "pkg-config"
        "postgresql-client"
        "power-diagnostics"
        "scons"
        "sed"
        "sox"
        "storage-health-tools"
        "swig"
        "usb-device-control"
        "video-device-tools"
        "vlc"
        "vmware-guest-tools"
        "wget"
        "xz"
    )

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_capability_map fedora

    assert_equal \
        "34" \
        "${#LWBS_CAPABILITY_PACKAGES[@]}"

    for capability in "${capabilities[@]}"; do
        if resolve_capability "$capability" >/dev/null; then
            continue
        fi

        printf 'Fedora capability did not resolve: %s\n' \
            "$capability" >&2

        return 1
    done

    assert_equal \
        $'gcc\ngcc-c++\nmake' \
        "$(resolve_capability build-toolchain)"

    assert_equal \
        "moby-engine" \
        "$(resolve_capability docker-engine)"

    assert_equal \
        "ffmpeg-free" \
        "$(resolve_capability ffmpeg)"

    assert_equal \
        "pkgconf-pkg-config" \
        "$(resolve_capability pkg-config)"

    assert_equal \
        "postgresql" \
        "$(resolve_capability postgresql-client)"

    assert_equal \
        "vlc" \
        "$(resolve_capability vlc)"

    assert_equal \
        "open-vm-tools" \
        "$(resolve_capability vmware-guest-tools)"

    assert_equal \
        "xz" \
        "$(resolve_capability xz)"

    reset_capability_map
}

test_fedora_rejects_unmapped_capability() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_capability_map fedora

    if resolve_capability \
        lwbs-unsupported-capability \
        >/dev/null 2>&1; then

        printf 'Fedora accepted an unsupported capability.\n' >&2
        return 1
    fi

    reset_capability_map
}

test_fedora_developer_profile_dry_run_plan() {
    local temp_dir
    local output_file
    local output
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    output_file="$temp_dir/fedora-developer-plan.out"

    DISTRO_ADAPTER_PROFILE="fedora"

    load_capability_map fedora

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false
    LWBS_TARGET_USER="test-user"

    # Every repository package is intentionally absent so the complete Fedora
    # developer workstation plan is visible.
    distro_package_state() {
        printf '%s\n' "absent"
    }

    account_require_query_commands() {
        return 0
    }

    account_user_exists() {
        return 0
    }

    # The Docker group is supplied by the planned Moby installation, so the
    # membership requirement must be deferred until package installation.
    account_group_exists() {
        return 1
    }

    run_profile developer >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "20" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_equal \
        "1" \
        "$LWBS_PLAN_ACCOUNT_ACTION_COUNT"

    modules="$(
        printf '%s\n' "${LWBS_PLAN_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\ncontainers-virtualization\ndatabase-tools' \
        "$modules"

    assert_contains \
        "$output" \
        "Developer Workstation"

    assert_contains \
        "$output" \
        "gcc [install]"

    assert_contains \
        "$output" \
        "gcc-c++ [install]"

    assert_contains \
        "$output" \
        "make [install]"

    assert_contains \
        "$output" \
        "moby-engine [install]"

    assert_contains \
        "$output" \
        "open-vm-tools [install]"

    assert_contains \
        "$output" \
        "postgresql [install]"

    assert_contains \
        "$output" \
        "test-user -> docker [add after module installation]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

test_fedora_security_profile_dry_run_plan() {
    local temp_dir
    local output_file
    local output
    local modules

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    output_file="$temp_dir/fedora-security-plan.out"

    DISTRO_ADAPTER_PROFILE="fedora"

    load_capability_map fedora

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    distro_package_state() {
        printf '%s\n' "absent"
    }

    # Fail2ban is not available until its planned package installation has
    # completed, so service management is deferred.
    service_manager_available() {
        return 0
    }

    query_service_presence() {
        printf '%s\n' "absent"
    }

    run_profile security >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "19" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "1" \
        "$LWBS_PLAN_SERVICE_ACTION_COUNT"

    modules="$(
        printf '%s\n' "${LWBS_PLAN_MODULES[@]}"
    )"

    assert_equal \
        $'common-utilities\ndevelopment-tools\nsecurity-tools' \
        "$modules"

    assert_contains \
        "$output" \
        "Security Workstation"

    assert_contains \
        "$output" \
        "gcc [install]"

    assert_contains \
        "$output" \
        "pkgconf-pkg-config [install]"

    assert_contains \
        "$output" \
        "fail2ban [install]"

    assert_contains \
        "$output" \
        "usbguard [install]"

    assert_contains \
        "$output" \
        "fail2ban.service [configure after install: enabled=enabled active=active]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

run_test \
    "recognize Fedora as a supported distribution" \
    test_fedora_supported_distribution_contract

run_test \
    "detect Fedora RPM package state" \
    test_fedora_package_state_detection

run_test \
    "resolve Fedora capability mappings" \
    test_fedora_capability_mapping

run_test \
    "reject unsupported Fedora capabilities" \
    test_fedora_rejects_unmapped_capability

run_test \
    "resolve the Fedora developer workstation dry-run plan" \
    test_fedora_developer_profile_dry_run_plan

run_test \
    "resolve the Fedora security workstation dry-run plan" \
    test_fedora_security_profile_dry_run_plan

finish_tests
