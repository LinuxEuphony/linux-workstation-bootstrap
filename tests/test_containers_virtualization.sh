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

test_containers_virtualization_module_contract() {
    local temp_dir
    local capabilities

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module containers-virtualization

    assert_equal \
        "containers-virtualization" \
        "$LWBS_MODULE_ID"

    assert_equal \
        "Containers and Virtualization" \
        "$LWBS_MODULE_NAME"

    assert_equal \
        "2" \
        "${#LWBS_MODULE_CAPABILITIES[@]}"

    capabilities="$(
        printf '%s\n' "${LWBS_MODULE_CAPABILITIES[@]}"
    )"

    assert_equal \
        $'docker-engine\nvmware-guest-tools' \
        "$capabilities"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"

    if ! declare -F module_verify >/dev/null 2>&1; then
        printf 'containers-virtualization does not provide module_verify.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_containers_virtualization_resolves_on_supported_distros() {
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
            docker-engine \
            vmware-guest-tools

        resolved="$(
            printf '%s\n' "${resolved_packages[@]}"
        )"

        assert_equal \
            $'docker.io\nopen-vm-tools' \
            "$resolved" \
            "container and virtualization mapping differs for $distro"

        reset_capability_map
    done
}

test_containers_virtualization_verification_succeeds() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module containers-virtualization

    # Verification dependency mocked so this test does not depend on which
    # tools happen to be installed on the developer workstation.
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 0
    }

    module_verify

    reset_module_contract
}

test_containers_virtualization_verification_detects_missing_command() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module containers-virtualization

    # Simulate an installed package set whose Docker command is unavailable.
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "docker" ]]
    }

    if module_verify >/dev/null 2>&1; then
        printf 'module_verify accepted a missing container command.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_containers_virtualization_can_be_selected_by_profile() {
    local temp_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    mkdir -p -- "$profile_dir"

    cat >"$profile_dir/containers-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "containers-test-profile"
}

profile_name() {
    printf '%s\n' "Containers Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the containers and virtualization module for testing."
}

profile_modules() {
    printf '%s\n' "containers-virtualization"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    load_profile containers-test-profile

    assert_equal \
        "containers-test-profile" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "1" \
        "${#LWBS_PROFILE_MODULES[@]}"

    assert_equal \
        "containers-virtualization" \
        "${LWBS_PROFILE_MODULES[0]}"

    reset_profile_contract
}

test_containers_virtualization_dry_run_execution_plan() {
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

    cat >"$profile_dir/containers-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "containers-test-profile"
}

profile_name() {
    printf '%s\n' "Containers Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the containers and virtualization module for planning tests."
}

profile_modules() {
    printf '%s\n' "containers-virtualization"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Planning needs package state but must not perform installation during
    # dry-run. Mark all requirements absent to produce a complete plan.
    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    run_profile containers-test-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "2" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_contains \
        "$output" \
        "Containers and Virtualization"

    assert_contains \
        "$output" \
        "docker.io [install]"

    assert_contains \
        "$output" \
        "open-vm-tools [install]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

run_test \
    "load the containers and virtualization module contract" \
    test_containers_virtualization_module_contract

run_test \
    "resolve container and virtualization capabilities on all supported distros" \
    test_containers_virtualization_resolves_on_supported_distros

run_test \
    "verify available container and virtualization tools" \
    test_containers_virtualization_verification_succeeds

run_test \
    "detect a missing container command during verification" \
    test_containers_virtualization_verification_detects_missing_command

run_test \
    "select containers and virtualization through a workstation profile" \
    test_containers_virtualization_can_be_selected_by_profile

run_test \
    "resolve containers and virtualization through a dry-run execution plan" \
    test_containers_virtualization_dry_run_execution_plan

finish_tests
