#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

write_fixture_module() {
    local module_directory="${1:-}"
    local module_id_value="${2:-}"
    local dependencies="${3:-}"
    local conflicts="${4:-}"

    cat >"$module_directory/$module_id_value.sh" <<EOF
module_id() {
    printf '%s\n' "$module_id_value"
}

module_name() {
    printf '%s\n' "$module_id_value"
}

module_description() {
    printf '%s\n' "Fixture module $module_id_value."
}

module_capabilities() {
    :
}

module_dependencies() {
    printf '%s\n' $dependencies
}

module_conflicts() {
    printf '%s\n' $conflicts
}

module_apply() {
    :
}
EOF
}

prepare_module_graph_test() {
    local temp_dir="${1:-}"
    local module_dir="$temp_dir/modules"

    setup_test_logging "$temp_dir"

    mkdir -p -- "$module_dir"

    LWBS_MODULES_DIR_OVERRIDE="$module_dir"

    reset_module_contract
    reset_module_graph_state
}

test_load_module_dependency_metadata() {
    local temp_dir
    local module_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module \
        "$module_dir" \
        "base" \
        "" \
        ""

    write_fixture_module \
        "$module_dir" \
        "app" \
        "base" \
        "legacy"

    load_module app

    assert_equal \
        "1" \
        "${#LWBS_MODULE_DEPENDENCIES[@]}"

    assert_equal \
        "base" \
        "${LWBS_MODULE_DEPENDENCIES[0]}"

    assert_equal \
        "1" \
        "${#LWBS_MODULE_CONFLICTS[@]}"

    assert_equal \
        "legacy" \
        "${LWBS_MODULE_CONFLICTS[0]}"
}

test_resolve_direct_dependency_before_module() {
    local temp_dir
    local module_dir

    local -a selected=("app")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module "$module_dir" "base" "" ""
    write_fixture_module "$module_dir" "app" "base" ""

    resolve_module_graph resolved selected excluded

    assert_equal \
        $'base\napp' \
        "$(printf '%s\n' "${resolved[@]}")"
}

test_resolve_transitive_dependencies() {
    local temp_dir
    local module_dir

    local -a selected=("app")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module "$module_dir" "base" "" ""
    write_fixture_module "$module_dir" "runtime" "base" ""
    write_fixture_module "$module_dir" "app" "runtime" ""

    resolve_module_graph resolved selected excluded

    assert_equal \
        $'base\nruntime\napp' \
        "$(printf '%s\n' "${resolved[@]}")"
}

test_deduplicate_shared_dependencies() {
    local temp_dir
    local module_dir

    local -a selected=("app-a" "app-b")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module "$module_dir" "base" "" ""
    write_fixture_module "$module_dir" "app-a" "base" ""
    write_fixture_module "$module_dir" "app-b" "base" ""

    resolve_module_graph resolved selected excluded

    assert_equal \
        $'base\napp-a\napp-b' \
        "$(printf '%s\n' "${resolved[@]}")"

    assert_equal \
        "3" \
        "${#resolved[@]}"
}

test_preserve_deterministic_root_order() {
    local temp_dir
    local module_dir

    local -a selected=("second" "first")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module "$module_dir" "first" "" ""
    write_fixture_module "$module_dir" "second" "" ""

    resolve_module_graph resolved selected excluded

    assert_equal \
        $'second\nfirst' \
        "$(printf '%s\n' "${resolved[@]}")"
}

test_detect_circular_dependency() {
    local temp_dir
    local module_dir
    local output
    local exit_code

    local -a selected=("alpha")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module "$module_dir" "alpha" "beta" ""
    write_fixture_module "$module_dir" "beta" "gamma" ""
    write_fixture_module "$module_dir" "gamma" "alpha" ""

    if output="$(
        resolve_module_graph resolved selected excluded 2>&1
    )"; then
        printf 'Circular dependency was accepted.\n' >&2
        return 1
    else
        exit_code=$?
    fi

    assert_equal "1" "$exit_code"

    assert_contains \
        "$output" \
        "circular module dependency detected"

    assert_contains \
        "$output" \
        "alpha -> beta -> gamma -> alpha"
}

test_detect_missing_dependency() {
    local temp_dir
    local module_dir
    local output

    local -a selected=("app")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module \
        "$module_dir" \
        "app" \
        "missing-runtime" \
        ""

    if output="$(
        resolve_module_graph resolved selected excluded 2>&1
    )"; then
        printf 'Missing dependency was accepted.\n' >&2
        return 1
    fi

    assert_contains \
        "$output" \
        "requires unavailable dependency: missing-runtime"
}

test_detect_module_conflict() {
    local temp_dir
    local module_dir
    local output

    local -a selected=("modern" "legacy")
    local -a excluded=()
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module \
        "$module_dir" \
        "modern" \
        "" \
        "legacy"

    write_fixture_module \
        "$module_dir" \
        "legacy" \
        "" \
        ""

    if output="$(
        resolve_module_graph resolved selected excluded 2>&1
    )"; then
        printf 'Conflicting modules were accepted.\n' >&2
        return 1
    fi

    assert_contains \
        "$output" \
        "modern conflicts with legacy"
}

test_reject_excluded_required_dependency() {
    local temp_dir
    local module_dir
    local output

    local -a selected=("app")
    local -a excluded=("base")
    local -a resolved=()

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"

    write_fixture_module "$module_dir" "base" "" ""
    write_fixture_module "$module_dir" "app" "base" ""

    if output="$(
        resolve_module_graph resolved selected excluded 2>&1
    )"; then
        printf 'Excluded required dependency was accepted.\n' >&2
        return 1
    fi

    assert_contains \
        "$output" \
        "app requires excluded module: base"
}

test_profile_and_cli_selection_use_graph_resolver() {
    local temp_dir
    local module_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_module_graph_test "$temp_dir"

    module_dir="$temp_dir/modules"
    profile_dir="$temp_dir/profiles"

    mkdir -p -- "$profile_dir"

    write_fixture_module "$module_dir" "base" "" ""
    write_fixture_module "$module_dir" "app" "base" ""
    write_fixture_module "$module_dir" "addon" "base" ""

    cat >"$profile_dir/test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "test-profile"
}

profile_name() {
    printf '%s\n' "Test Profile"
}

profile_description() {
    printf '%s\n' "Module graph profile fixture."
}

profile_modules() {
    printf '%s\n' "app"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    LWBS_REQUESTED_MODULES=("addon")
    LWBS_EXCLUDED_MODULES=()

    load_profile test-profile

    assert_equal \
        $'base\napp\naddon' \
        "$(printf '%s\n' "${LWBS_PROFILE_MODULES[@]}")"

    assert_equal \
        "3" \
        "${#LWBS_PROFILE_MODULES[@]}"
}

run_test \
    "capture module dependency and conflict metadata" \
    test_load_module_dependency_metadata

run_test \
    "resolve a direct dependency before its dependent module" \
    test_resolve_direct_dependency_before_module

run_test \
    "resolve transitive module dependencies" \
    test_resolve_transitive_dependencies

run_test \
    "deduplicate shared module dependencies" \
    test_deduplicate_shared_dependencies

run_test \
    "preserve deterministic root module ordering" \
    test_preserve_deterministic_root_order

run_test \
    "detect circular module dependencies" \
    test_detect_circular_dependency

run_test \
    "reject unavailable required dependencies" \
    test_detect_missing_dependency

run_test \
    "reject conflicting resolved modules" \
    test_detect_module_conflict

run_test \
    "reject explicitly excluded required dependencies" \
    test_reject_excluded_required_dependency

run_test \
    "resolve dependencies for profile and CLI module selections" \
    test_profile_and_cli_selection_use_graph_resolver

finish_tests
