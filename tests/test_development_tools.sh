#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# Source the complete bootstrap framework because these tests exercise the
# module through capability, profile, and execution-plan integration.
# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

test_development_tools_module_contract() {
    local temp_dir
    local capabilities

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module development-tools

    assert_equal \
        "development-tools" \
        "$LWBS_MODULE_ID"

    assert_equal \
        "Development Tools" \
        "$LWBS_MODULE_NAME"

    assert_equal \
        "9" \
        "${#LWBS_MODULE_CAPABILITIES[@]}"

    capabilities="$(
        printf '%s\n' "${LWBS_MODULE_CAPABILITIES[@]}"
    )"

    assert_equal \
        $'build-toolchain\ngit\ncmake\npkg-config\nbison\nflex\nswig\nscons\ncloc' \
        "$capabilities"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"

    if ! declare -F module_verify >/dev/null 2>&1; then
        printf 'development-tools does not provide module_verify.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_development_tools_resolve_on_supported_distros() {
    local temp_dir
    local distro
    local resolved

    local -a resolved_packages=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    for distro in ubuntu debian kali; do
        load_capability_map "$distro"

        resolved_packages=()

        resolve_capabilities \
            resolved_packages \
            build-toolchain \
            git \
            cmake \
            pkg-config \
            bison \
            flex \
            swig \
            scons \
            cloc

        resolved="$(
            printf '%s\n' "${resolved_packages[@]}"
        )"

        assert_equal \
            $'build-essential\ngit\ncmake\npkg-config\nbison\nflex\nswig\nscons\ncloc' \
            "$resolved" \
            "development tool capability mapping differs for $distro"

        reset_capability_map
    done
}

test_development_tools_verification_succeeds() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module development-tools

    # Verification dependency mocked so this test does not depend on the
    # development tools installed on the developer workstation.
    # shellcheck disable=SC2329
    command_exists() {
        return 0
    }

    module_verify

    reset_module_contract
}

test_development_tools_verification_detects_missing_command() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module development-tools

    # Simulate an installed package set whose expected compiler command is
    # unavailable so module-level verification must reject the result.
    # shellcheck disable=SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "gcc" ]]
    }

    if module_verify >/dev/null 2>&1; then
        printf 'module_verify accepted a missing development command.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_development_tools_can_be_selected_by_profile() {
    local temp_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    mkdir -p -- "$profile_dir"

    cat >"$profile_dir/development-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "development-test-profile"
}

profile_name() {
    printf '%s\n' "Development Tools Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the development tools module for testing."
}

profile_modules() {
    printf '%s\n' "development-tools"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    load_profile development-test-profile

    assert_equal \
        "development-test-profile" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "1" \
        "${#LWBS_PROFILE_MODULES[@]}"

    assert_equal \
        "development-tools" \
        "${LWBS_PROFILE_MODULES[0]}"

    reset_profile_contract
}

test_development_tools_dry_run_execution_plan() {
    local temp_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/execution-plan.out"

    mkdir -p -- "$profile_dir"

    cat >"$profile_dir/development-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "development-test-profile"
}

profile_name() {
    printf '%s\n' "Development Tools Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the development tools module for planning tests."
}

profile_modules() {
    printf '%s\n' "development-tools"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Planning needs package state but must not perform installation during
    # dry-run. Mark all requirements absent to produce a complete plan.
    # shellcheck disable=SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    run_profile development-test-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "9" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_contains \
        "$output" \
        "Development Tools"

    assert_contains \
        "$output" \
        "build-essential [install]"

    assert_contains \
        "$output" \
        "git [install]"

    assert_contains \
        "$output" \
        "cmake [install]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

run_test \
    "load the development tools module contract" \
    test_development_tools_module_contract

run_test \
    "resolve development capabilities on all supported distros" \
    test_development_tools_resolve_on_supported_distros

run_test \
    "verify available development tools" \
    test_development_tools_verification_succeeds

run_test \
    "detect a missing development command during verification" \
    test_development_tools_verification_detects_missing_command

run_test \
    "select development tools through a workstation profile" \
    test_development_tools_can_be_selected_by_profile

run_test \
    "resolve development tools through a dry-run execution plan" \
    test_development_tools_dry_run_execution_plan

finish_tests
