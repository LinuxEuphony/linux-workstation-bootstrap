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

test_common_utilities_module_contract() {
    local temp_dir
    local capabilities

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module common-utilities

    assert_equal \
        "common-utilities" \
        "$LWBS_MODULE_ID"

    assert_equal \
        "Common Utilities" \
        "$LWBS_MODULE_NAME"

    assert_equal \
        "6" \
        "${#LWBS_MODULE_CAPABILITIES[@]}"

    capabilities="$(
        printf '%s\n' "${LWBS_MODULE_CAPABILITIES[@]}"
    )"

    assert_equal \
        $'curl\ndos2unix\nnano\nsed\nwget\nxz' \
        "$capabilities"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"

    if ! declare -F module_verify >/dev/null 2>&1; then
        printf 'common-utilities does not provide module_verify.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_common_utilities_resolve_on_supported_distros() {
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
            curl \
            dos2unix \
            nano \
            sed \
            wget \
            xz

        resolved="$(
            printf '%s\n' "${resolved_packages[@]}"
        )"

        assert_equal \
            $'curl\ndos2unix\nnano\nsed\nwget\nxz-utils' \
            "$resolved" \
            "common utility capability mapping differs for $distro"

        reset_capability_map
    done
}

test_common_utilities_verification_succeeds() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module common-utilities

    # Verification dependency mocked so this test does not depend on which
    # utilities happen to be installed on the developer workstation.
    # shellcheck disable=SC2329
    command_exists() {
        return 0
    }

    module_verify

    reset_module_contract
}

test_common_utilities_verification_detects_missing_command() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module common-utilities

    # Simulate one package being present while its expected executable is not
    # usable so module-level verification must reject the result.
    # shellcheck disable=SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "dos2unix" ]]
    }

    if module_verify >/dev/null 2>&1; then
        printf 'module_verify accepted a missing required utility.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_common_utilities_can_be_selected_by_profile() {
    local temp_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    mkdir -p -- "$profile_dir"

    cat >"$profile_dir/common-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "common-test-profile"
}

profile_name() {
    printf '%s\n' "Common Utilities Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the common utilities module for testing."
}

profile_modules() {
    printf '%s\n' "common-utilities"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    load_profile common-test-profile

    assert_equal \
        "common-test-profile" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "1" \
        "${#LWBS_PROFILE_MODULES[@]}"

    assert_equal \
        "common-utilities" \
        "${LWBS_PROFILE_MODULES[0]}"

    reset_profile_contract
}

test_common_utilities_dry_run_execution_plan() {
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

    cat >"$profile_dir/common-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "common-test-profile"
}

profile_name() {
    printf '%s\n' "Common Utilities Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the common utilities module for planning tests."
}

profile_modules() {
    printf '%s\n' "common-utilities"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # Planning needs package state but must not perform installation during
    # dry-run. All requirements are marked absent to produce a complete plan.
    # shellcheck disable=SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    # Redirect output to a file rather than using command substitution.
    # Command substitution would execute run_profile in a subshell and discard
    # the execution-plan state that this test needs to inspect afterward.
    run_profile common-test-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "6" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_contains \
        "$output" \
        "Common Utilities"

    assert_contains \
        "$output" \
        "curl [install]"

    assert_contains \
        "$output" \
        "xz-utils [install]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

run_test \
    "load the common utilities module contract" \
    test_common_utilities_module_contract

run_test \
    "resolve common utility capabilities on all supported distros" \
    test_common_utilities_resolve_on_supported_distros

run_test \
    "verify available common utilities" \
    test_common_utilities_verification_succeeds

run_test \
    "detect a missing common utility during verification" \
    test_common_utilities_verification_detects_missing_command

run_test \
    "select common utilities through a workstation profile" \
    test_common_utilities_can_be_selected_by_profile

run_test \
    "resolve common utilities through a dry-run execution plan" \
    test_common_utilities_dry_run_execution_plan

finish_tests
