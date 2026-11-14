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

test_desktop_media_module_contract() {
    local temp_dir
    local capabilities

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module desktop-media

    assert_equal \
        "desktop-media" \
        "$LWBS_MODULE_ID"

    assert_equal \
        "Desktop and Media" \
        "$LWBS_MODULE_NAME"

    assert_equal \
        "8" \
        "${#LWBS_MODULE_CAPABILITIES[@]}"

    capabilities="$(
        printf '%s\n' "${LWBS_MODULE_CAPABILITIES[@]}"
    )"

    assert_equal \
        $'gimp\ninkscape\nvlc\nffmpeg\nsox\ndarktable\ncalibre\npavucontrol' \
        "$capabilities"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_EXTERNAL_INSTALLERS[@]}"

    if ! declare -F module_verify >/dev/null 2>&1; then
        printf 'desktop-media does not provide module_verify.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_desktop_media_resolves_on_supported_distros() {
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
            gimp \
            inkscape \
            vlc \
            ffmpeg \
            sox \
            darktable \
            calibre \
            pavucontrol

        resolved="$(
            printf '%s\n' "${resolved_packages[@]}"
        )"

        assert_equal \
            $'gimp\ninkscape\nvlc\nffmpeg\nsox\ndarktable\ncalibre\npavucontrol' \
            "$resolved" \
            "desktop and media capability mapping differs for $distro"

        reset_capability_map
    done
}

test_desktop_media_verification_succeeds() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module desktop-media

    # Verification dependency mocked so this test does not depend on desktop
    # applications installed on the developer workstation.
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 0
    }

    module_verify

    reset_module_contract
}

test_desktop_media_verification_detects_missing_command() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    load_module desktop-media

    # Simulate an installed package set whose expected media command is
    # unavailable so module-level verification must reject the result.
    # shellcheck disable=SC2317,SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "ffmpeg" ]]
    }

    if module_verify >/dev/null 2>&1; then
        printf 'module_verify accepted a missing desktop or media command.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_desktop_media_can_be_selected_by_profile() {
    local temp_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    mkdir -p -- "$profile_dir"

    cat >"$profile_dir/desktop-media-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "desktop-media-test-profile"
}

profile_name() {
    printf '%s\n' "Desktop Media Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the desktop and media module for testing."
}

profile_modules() {
    printf '%s\n' "desktop-media"
}
EOF

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    load_profile desktop-media-test-profile

    assert_equal \
        "desktop-media-test-profile" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "1" \
        "${#LWBS_PROFILE_MODULES[@]}"

    assert_equal \
        "desktop-media" \
        "${LWBS_PROFILE_MODULES[0]}"

    reset_profile_contract
}

test_desktop_media_dry_run_execution_plan() {
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

    cat >"$profile_dir/desktop-media-test-profile.sh" <<'EOF'
profile_id() {
    printf '%s\n' "desktop-media-test-profile"
}

profile_name() {
    printf '%s\n' "Desktop Media Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the desktop and media module for planning tests."
}

profile_modules() {
    printf '%s\n' "desktop-media"
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

    run_profile desktop-media-test-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "8" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SKIP_ACTION_COUNT"

    assert_contains \
        "$output" \
        "Desktop and Media"

    assert_contains \
        "$output" \
        "gimp [install]"

    assert_contains \
        "$output" \
        "vlc [install]"

    assert_contains \
        "$output" \
        "ffmpeg [install]"

    assert_contains \
        "$output" \
        "pavucontrol [install]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

run_test \
    "load the desktop and media module contract" \
    test_desktop_media_module_contract

run_test \
    "resolve desktop and media capabilities on all supported distros" \
    test_desktop_media_resolves_on_supported_distros

run_test \
    "verify available desktop and media applications" \
    test_desktop_media_verification_succeeds

run_test \
    "detect a missing desktop or media command during verification" \
    test_desktop_media_verification_detects_missing_command

run_test \
    "select desktop and media through a workstation profile" \
    test_desktop_media_can_be_selected_by_profile

run_test \
    "resolve desktop and media through a dry-run execution plan" \
    test_desktop_media_dry_run_execution_plan

finish_tests
