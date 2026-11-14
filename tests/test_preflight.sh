#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

prepare_preflight_test_state() {
    local temp_dir="${1:-}"

    setup_test_logging "$temp_dir"

    reset_execution_plan
    reset_preflight_state

    LWBS_PLAN_STATUS="resolved"
    LWBS_PLAN_PROFILE_ID="test"
    LWBS_PLAN_PROFILE_NAME="Test Profile"
    LWBS_PLAN_DISTRO_PROFILE="ubuntu"

    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_CAPABILITY_PROFILE="ubuntu"

    SYSTEM_ARCH="amd64"
    SYSTEM_DISTRO_FAMILY="debian"
    SYSTEM_PACKAGE_MANAGER="apt"

    LWBS_REQUESTED_MODULES=()
    LWBS_EXCLUDED_MODULES=()
}

test_supported_architecture_passes() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    preflight_check_architecture

    assert_equal \
        "0" \
        "${#LWBS_PREFLIGHT_FAILURES[@]}"
}

test_unsupported_architecture_is_rejected() {
    local temp_dir
    local failures

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    SYSTEM_ARCH="riscv64"

    preflight_check_architecture

    failures="$(
        printf '%s\n' "${LWBS_PREFLIGHT_FAILURES[@]}"
    )"

    assert_contains \
        "$failures" \
        "Architecture riscv64 is not supported"
}

test_privilege_is_required_for_package_installation() {
    local temp_dir
    local failures

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    LWBS_PLAN_MODULES=("sample")
    LWBS_PLAN_MODULE_INSTALL_PACKAGES["sample"]="example-package"

    # shellcheck disable=SC2317,SC2329
    preflight_is_root() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 1
    }

    preflight_check_required_privilege

    failures="$(
        printf '%s\n' "${LWBS_PREFLIGHT_FAILURES[@]}"
    )"

    assert_contains \
        "$failures" \
        "requires root privileges"
}

test_privilege_is_not_required_for_satisfied_plan() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    LWBS_PLAN_MODULES=("sample")
    LWBS_PLAN_MODULE_SKIP_PACKAGES["sample"]="example-package"

    # shellcheck disable=SC2317,SC2329
    preflight_is_root() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 1
    }

    preflight_check_required_privilege

    assert_equal \
        "0" \
        "${#LWBS_PREFLIGHT_FAILURES[@]}"
}

test_unusable_state_location_is_reported() {
    local temp_dir
    local failures

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    LWBS_STATE_DIR="$temp_dir/does-not-exist"

    preflight_check_logging_paths

    failures="$(
        printf '%s\n' "${LWBS_PREFLIGHT_FAILURES[@]}"
    )"

    assert_contains \
        "$failures" \
        "Application state directory is unavailable or not writable"
}

test_module_can_require_additional_command() {
    local temp_dir
    local module_dir
    local failures

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    module_dir="$temp_dir/modules"
    mkdir -p -- "$module_dir"

    cat >"$module_dir/sample.sh" <<'EOF'
module_id() {
    printf '%s\n' "sample"
}

module_name() {
    printf '%s\n' "Sample"
}

module_description() {
    printf '%s\n' "Sample preflight module."
}

module_capabilities() {
    :
}

module_apply() {
    :
}

module_preflight_requirements() {
    printf '%s\n' "command:sample-required-command"
}
EOF

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"

    LWBS_PLAN_MODULES=("sample")
    LWBS_PLAN_MODULE_NAMES["sample"]="Sample"
    LWBS_PLAN_MODULE_HAS_APPLY["sample"]="true"

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "sample-required-command" ]]
    }

    preflight_collect_module_requirements

    failures="$(
        printf '%s\n' "${LWBS_PREFLIGHT_FAILURES[@]}"
    )"

    assert_contains \
        "$failures" \
        "sample-required-command"
}

test_network_is_not_checked_without_planned_action() {
    local temp_dir
    local module_dir
    local marker

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    module_dir="$temp_dir/modules"
    marker="$temp_dir/network-probed"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/sample.sh" <<'EOF'
module_id() {
    printf '%s\n' "sample"
}

module_name() {
    printf '%s\n' "Sample"
}

module_description() {
    printf '%s\n' "Sample network module."
}

module_capabilities() {
    :
}

module_verify() {
    :
}

module_preflight_requirements() {
    printf '%s\n' "network:example.com:443"
}
EOF

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"

    LWBS_PLAN_MODULES=("sample")
    LWBS_PLAN_MODULE_NAMES["sample"]="Sample"
    LWBS_PLAN_MODULE_HAS_APPLY["sample"]="false"

    # shellcheck disable=SC2317,SC2329
    preflight_network_available() {
        touch -- "$marker"
        return 1
    }

    preflight_collect_module_requirements

    assert_not_exists \
        "$marker" \
        "network was checked even though the module had no planned action"

    assert_equal \
        "0" \
        "${#LWBS_PREFLIGHT_FAILURES[@]}"
}

test_network_is_checked_when_required_by_planned_action() {
    local temp_dir
    local module_dir
    local failures

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    module_dir="$temp_dir/modules"

    mkdir -p -- "$module_dir"

    cat >"$module_dir/sample.sh" <<'EOF'
module_id() {
    printf '%s\n' "sample"
}

module_name() {
    printf '%s\n' "Sample"
}

module_description() {
    printf '%s\n' "Sample network module."
}

module_capabilities() {
    :
}

module_apply() {
    :
}

module_preflight_requirements() {
    printf '%s\n' "network:example.com:443"
}
EOF

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"

    LWBS_PLAN_MODULES=("sample")
    LWBS_PLAN_MODULE_NAMES["sample"]="Sample"
    LWBS_PLAN_MODULE_HAS_APPLY["sample"]="true"

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    preflight_network_available() {
        return 1
    }

    preflight_collect_module_requirements

    failures="$(
        printf '%s\n' "${LWBS_PREFLIGHT_FAILURES[@]}"
    )"

    assert_contains \
        "$failures" \
        "example.com:443"
}

test_external_installer_can_contribute_requirements() {
    local temp_dir
    local installer_dir
    local external_key
    local failures

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    installer_dir="$temp_dir/installers"
    mkdir -p -- "$installer_dir"

    cat >"$installer_dir/sample-external.sh" <<'EOF'
external_id() {
    printf '%s\n' "sample-external"
}

external_name() {
    printf '%s\n' "Sample External"
}

external_description() {
    printf '%s\n' "Sample external installer."
}

external_method() {
    printf '%s\n' "script"
}

external_state() {
    printf '%s\n' "absent"
}

external_script_apply() {
    :
}

external_preflight_requirements() {
    printf '%s\n' "command:sample-external-command"
}
EOF

    LWBS_EXTERNAL_INSTALLERS_DIR_OVERRIDE="$installer_dir"

    LWBS_PLAN_MODULES=("sample")
    LWBS_PLAN_MODULE_EXTERNALS["sample"]="sample-external"

    external_key="$(
        execution_plan_external_key \
            "sample" \
            "sample-external"
    )"

    LWBS_PLAN_EXTERNAL_ACTIONS["$external_key"]="install"

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "sample-external-command" ]]
    }

    preflight_collect_external_requirements

    failures="$(
        printf '%s\n' "${LWBS_PREFLIGHT_FAILURES[@]}"
    )"

    assert_contains \
        "$failures" \
        "sample-external-command"
}

test_preflight_resolution_does_not_execute_module_apply() {
    local temp_dir
    local profile_dir
    local module_dir
    local marker

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_preflight_test_state "$temp_dir"

    profile_dir="$temp_dir/profiles"
    module_dir="$temp_dir/modules"
    marker="$temp_dir/applied"

    mkdir -p \
        "$profile_dir" \
        "$module_dir"

    cat >"$profile_dir/preflight-test.sh" <<'EOF'
profile_id() {
    printf '%s\n' "preflight-test"
}

profile_name() {
    printf '%s\n' "Preflight Test"
}

profile_description() {
    printf '%s\n' "Preflight integration test."
}

profile_modules() {
    printf '%s\n' "sample"
}
EOF

    cat >"$module_dir/sample.sh" <<EOF
module_id() {
    printf '%s\n' "sample"
}

module_name() {
    printf '%s\n' "Sample"
}

module_description() {
    printf '%s\n' "Sample integration module."
}

module_capabilities() {
    :
}

module_apply() {
    touch "$marker"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"
    LWBS_MODULES_DIR_OVERRIDE="$module_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"
    LWBS_CAPABILITY_PROFILE="ubuntu"

    # shellcheck disable=SC2317,SC2329
    validate_distro_adapter() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    distro_validate_environment() {
        return 0
    }

    validate_profile_preflight preflight-test

    assert_equal \
        "passed" \
        "$LWBS_PREFLIGHT_STATUS"

    assert_not_exists \
        "$marker" \
        "preflight executed module_apply"

    assert_equal \
        "empty" \
        "$LWBS_PLAN_STATUS"
}

run_test \
    "accept a supported distro architecture combination" \
    test_supported_architecture_passes

run_test \
    "reject an unsupported distro architecture combination" \
    test_unsupported_architecture_is_rejected

run_test \
    "require privilege escalation for package installation" \
    test_privilege_is_required_for_package_installation

run_test \
    "avoid privilege checks for an already satisfied plan" \
    test_privilege_is_not_required_for_satisfied_plan

run_test \
    "report an unusable application state location" \
    test_unusable_state_location_is_reported

run_test \
    "allow modules to contribute command requirements" \
    test_module_can_require_additional_command

run_test \
    "avoid network checks when no planned action requires them" \
    test_network_is_not_checked_without_planned_action

run_test \
    "check network connectivity when a planned action requires it" \
    test_network_is_checked_when_required_by_planned_action

run_test \
    "allow external installers to contribute preflight requirements" \
    test_external_installer_can_contribute_requirements

run_test \
    "keep profile preflight resolution read-only" \
    test_preflight_resolution_does_not_execute_module_apply

finish_tests
