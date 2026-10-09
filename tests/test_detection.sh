#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../config/defaults.sh
source "$REPO_ROOT/config/defaults.sh"

# shellcheck source=../lib/detect.sh
source "$REPO_ROOT/lib/detect.sh"

test_detect_ubuntu_fixture() {
    LWBS_OS_RELEASE_OVERRIDE="$TEST_DIR/fixtures/os-release/ubuntu"
    LWBS_ARCH_OVERRIDE="x86_64"

    detect_system

    assert_equal "ubuntu" "$SYSTEM_DISTRO_ID"
    assert_equal "Ubuntu 26.04.1 LTS" "$SYSTEM_DISTRO_NAME"
    assert_equal "26.04" "$SYSTEM_DISTRO_VERSION"
    assert_equal "resolute" "$SYSTEM_DISTRO_CODENAME"
    assert_equal "debian" "$SYSTEM_DISTRO_FAMILY"
    assert_equal "amd64" "$SYSTEM_ARCH"
    assert_equal "apt" "$SYSTEM_PACKAGE_MANAGER"
}

test_detect_fedora_family() {
    LWBS_OS_RELEASE_OVERRIDE="$TEST_DIR/fixtures/os-release/fedora"
    LWBS_ARCH_OVERRIDE="x86_64"

    detect_system

    assert_equal "fedora" "$SYSTEM_DISTRO_ID"
    assert_equal "rpm" "$SYSTEM_DISTRO_FAMILY"
    assert_equal "dnf" "$SYSTEM_PACKAGE_MANAGER"
    assert_equal "amd64" "$SYSTEM_ARCH"
}

test_detect_family_from_id_like() {
    LWBS_OS_RELEASE_OVERRIDE="$TEST_DIR/fixtures/os-release/derived-debian"
    LWBS_ARCH_OVERRIDE="aarch64"

    detect_system

    assert_equal "examplelinux" "$SYSTEM_DISTRO_ID"
    assert_equal "debian" "$SYSTEM_DISTRO_FAMILY"
    assert_equal "apt" "$SYSTEM_PACKAGE_MANAGER"
    assert_equal "arm64" "$SYSTEM_ARCH"
}

test_detect_unknown_distribution_family() {
    LWBS_OS_RELEASE_OVERRIDE="$TEST_DIR/fixtures/os-release/unknown"
    LWBS_ARCH_OVERRIDE="riscv64"

    detect_system

    assert_equal "unknown" "$SYSTEM_DISTRO_FAMILY"
    assert_equal "unknown" "$SYSTEM_PACKAGE_MANAGER"
    assert_equal "riscv64" "$SYSTEM_ARCH"
}

test_architecture_normalization() {
    LWBS_ARCH_OVERRIDE="x86_64"
    assert_equal "amd64" "$(detect_architecture)"

    LWBS_ARCH_OVERRIDE="aarch64"
    assert_equal "arm64" "$(detect_architecture)"

    LWBS_ARCH_OVERRIDE="i686"
    assert_equal "i386" "$(detect_architecture)"

    LWBS_ARCH_OVERRIDE="riscv64"
    assert_equal "riscv64" "$(detect_architecture)"
}

test_missing_os_release_fails() {
    LWBS_OS_RELEASE_OVERRIDE="/tmp/lwbs-os-release-does-not-exist-$$"

    if detect_system >/dev/null 2>&1; then
        printf 'detect_system unexpectedly accepted a missing os-release file.\n' \
            >&2
        return 1
    fi

    return 0
}

run_test \
    "detect Ubuntu from controlled os-release fixture" \
    test_detect_ubuntu_fixture

run_test \
    "detect Fedora family without requiring Fedora support" \
    test_detect_fedora_family

run_test \
    "resolve distro family through ID_LIKE" \
    test_detect_family_from_id_like

run_test \
    "handle an unknown distribution family" \
    test_detect_unknown_distribution_family

run_test \
    "normalize known architectures and preserve unknown ones" \
    test_architecture_normalization

run_test \
    "reject an unreadable os-release source" \
    test_missing_os_release_fails

finish_tests