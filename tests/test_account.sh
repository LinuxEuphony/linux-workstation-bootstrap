#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2329

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

TEST_ACCOUNT_USER_NAME="developer"
TEST_ACCOUNT_USER_EXISTS=true
TEST_ACCOUNT_GROUP_EXISTS=true
TEST_ACCOUNT_MEMBER=false
TEST_ACCOUNT_PRIVILEGED_USED=false

install_account_test_mocks() {
    id() {
        case "${1:-}" in
            -un)
                printf '%s\n' "$TEST_ACCOUNT_USER_NAME"
                ;;

            -u)
                if "$TEST_ACCOUNT_USER_EXISTS" &&
                    [[ "${2:-}" == "$TEST_ACCOUNT_USER_NAME" ]]; then

                    printf '%s\n' "1000"
                    return 0
                fi

                return 1
                ;;

            -nG)
                if ! "$TEST_ACCOUNT_USER_EXISTS" ||
                    [[ "${2:-}" != "$TEST_ACCOUNT_USER_NAME" ]]; then

                    return 1
                fi

                if "$TEST_ACCOUNT_MEMBER"; then
                    printf '%s\n' "$TEST_ACCOUNT_USER_NAME docker"
                else
                    printf '%s\n' "$TEST_ACCOUNT_USER_NAME"
                fi
                ;;

            *)
                return 1
                ;;
        esac
    }

    getent() {
        if [[ "${1:-}" != "group" ||
            "${2:-}" != "docker" ]]; then

            return 2
        fi

        if "$TEST_ACCOUNT_GROUP_EXISTS"; then
            printf '%s\n' "docker:x:999:"
            return 0
        fi

        return 2
    }

    usermod() {
        if [[ "${1:-}" != "-a" ||
            "${2:-}" != "-G" ||
            "${3:-}" != "docker" ||
            "${4:-}" != "$TEST_ACCOUNT_USER_NAME" ]]; then

            return 1
        fi

        TEST_ACCOUNT_MEMBER=true
        return 0
    }

    run_privileged_command() {
        TEST_ACCOUNT_PRIVILEGED_USED=true
        "$@"
    }
}

prepare_account_test() {
    local temp_dir="${1:-}"

    setup_test_logging "$temp_dir"

    reset_execution_plan
    reset_execution_results
    reset_restart_tracking

    TEST_ACCOUNT_USER_NAME="developer"
    TEST_ACCOUNT_USER_EXISTS=true
    TEST_ACCOUNT_GROUP_EXISTS=true
    TEST_ACCOUNT_MEMBER=false
    TEST_ACCOUNT_PRIVILEGED_USED=false

    install_account_test_mocks

    LWBS_TARGET_USER_OVERRIDE="developer"

    initialize_target_workstation_user
}

test_resolve_sudo_target_user() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    install_account_test_mocks

    TEST_ACCOUNT_USER_NAME="alice"
    TEST_ACCOUNT_USER_EXISTS=true

    LWBS_TARGET_USER_OVERRIDE=""
    SUDO_USER="alice"

    initialize_target_workstation_user

    assert_equal \
        "alice" \
        "$LWBS_TARGET_USER"

    assert_equal \
        "sudo" \
        "$LWBS_TARGET_USER_SOURCE"
}

test_reject_missing_target_user() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    install_account_test_mocks

    TEST_ACCOUNT_USER_EXISTS=false
    LWBS_TARGET_USER_OVERRIDE="developer"

    if initialize_target_workstation_user >/dev/null 2>&1; then
        printf 'Missing target user was accepted.\n' >&2
        return 1
    fi
}

test_skip_existing_membership() {
    local temp_dir
    local plan_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    TEST_ACCOUNT_MEMBER=true

    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    plan_module_group_memberships sample

    plan_key="$(account_group_plan_key sample docker)"

    assert_equal \
        "skip" \
        "${LWBS_PLAN_GROUP_ACTIONS[$plan_key]}"

    assert_equal \
        "0" \
        "$LWBS_PLAN_ACCOUNT_ACTION_COUNT"
}

test_plan_missing_membership() {
    local temp_dir
    local plan_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    plan_module_group_memberships sample

    plan_key="$(account_group_plan_key sample docker)"

    assert_equal \
        "add" \
        "${LWBS_PLAN_GROUP_ACTIONS[$plan_key]}"

    assert_equal \
        "1" \
        "$LWBS_PLAN_ACCOUNT_ACTION_COUNT"

    assert_equal \
        "1" \
        "${#LWBS_PLANNED_RESTART_KEYS[@]}"
}

test_defer_group_created_by_package_install() {
    local temp_dir
    local plan_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    TEST_ACCOUNT_GROUP_EXISTS=false

    LWBS_PLAN_MODULE_INSTALL_PACKAGES["sample"]="docker.io"
    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    plan_module_group_memberships sample

    plan_key="$(account_group_plan_key sample docker)"

    assert_equal \
        "deferred" \
        "${LWBS_PLAN_GROUP_ACTIONS[$plan_key]}"
}

test_reject_missing_group_without_creator() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    TEST_ACCOUNT_GROUP_EXISTS=false

    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    if plan_module_group_memberships sample >/dev/null 2>&1; then
        printf 'Missing group was accepted without a planned creator.\n' >&2
        return 1
    fi
}

test_execute_membership_through_privileged_layer() {
    local temp_dir
    local result_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    plan_module_group_memberships sample

    execute_planned_group_memberships sample

    if ! "$TEST_ACCOUNT_PRIVILEGED_USED"; then
        printf 'Group membership bypassed privileged execution.\n' >&2
        return 1
    fi

    if ! "$TEST_ACCOUNT_MEMBER"; then
        printf 'Group membership was not applied.\n' >&2
        return 1
    fi

    result_key="$(account_result_key sample docker)"

    assert_equal \
        "successful" \
        "${LWBS_RESULT_STATUS[$result_key]}"

    assert_equal \
        "1" \
        "${#LWBS_RESTART_KEYS[@]}"
}

test_deduplicate_group_across_modules() {
    local temp_dir
    local second_key

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    plan_module_group_memberships first
    plan_module_group_memberships second

    second_key="$(account_group_plan_key second docker)"

    assert_equal \
        "shared" \
        "${LWBS_PLAN_GROUP_ACTIONS[$second_key]}"

    assert_equal \
        "1" \
        "$LWBS_PLAN_ACCOUNT_ACTION_COUNT"
}

test_account_plan_requires_privilege() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    LWBS_MODULE_GROUP_MEMBERSHIPS=("docker")

    plan_module_group_memberships sample

    if ! account_plan_requires_privilege; then
        printf 'Group membership plan did not require privilege escalation.\n' >&2
        return 1
    fi
}

test_containers_module_declares_docker_group() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_account_test "$temp_dir"

    load_module containers-virtualization

    assert_equal \
        "1" \
        "${#LWBS_MODULE_GROUP_MEMBERSHIPS[@]}"

    assert_equal \
        "docker" \
        "${LWBS_MODULE_GROUP_MEMBERSHIPS[0]}"
}

run_test \
    "resolve the target workstation user from sudo context" \
    test_resolve_sudo_target_user

run_test \
    "reject a missing target workstation user" \
    test_reject_missing_target_user

run_test \
    "skip an already satisfied group membership" \
    test_skip_existing_membership

run_test \
    "plan a missing group membership" \
    test_plan_missing_membership

run_test \
    "defer a group that may be created by package installation" \
    test_defer_group_created_by_package_install

run_test \
    "reject a missing group with no planned creator" \
    test_reject_missing_group_without_creator

run_test \
    "apply group membership through privileged execution" \
    test_execute_membership_through_privileged_layer

run_test \
    "deduplicate the same group requirement across modules" \
    test_deduplicate_group_across_modules

run_test \
    "require privilege for account changes" \
    test_account_plan_requires_privilege

run_test \
    "declare Docker group membership from the container module" \
    test_containers_module_declares_docker_group

finish_tests