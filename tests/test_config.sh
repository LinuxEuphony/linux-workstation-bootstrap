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

# shellcheck source=../lib/config.sh
source "$REPO_ROOT/lib/config.sh"

test_missing_config_uses_defaults() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    LWBS_USER_CONFIG_PATH_OVERRIDE="$temp_dir/does-not-exist.conf"

    load_user_config

    assert_equal "auto" "$LWBS_CONFIG_DISTRO_PROFILE"
}

test_valid_config_override() {
    local temp_dir
    local config_file

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    config_file="$temp_dir/config.conf"

    cat >"$config_file" <<'EOF'
# Linux Workstation Bootstrap

distro_profile=ubuntu
EOF

    LWBS_USER_CONFIG_PATH_OVERRIDE="$config_file"

    load_user_config

    assert_equal "ubuntu" "$LWBS_CONFIG_DISTRO_PROFILE"
}

test_invalid_config_key_fails() {
    local temp_dir
    local config_file

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    config_file="$temp_dir/config.conf"

    printf '%s\n' \
        'unsupported_setting=true' \
        >"$config_file"

    LWBS_USER_CONFIG_PATH_OVERRIDE="$config_file"

    if load_user_config >/dev/null 2>&1; then
        printf 'Unsupported configuration setting was accepted.\n' >&2
        return 1
    fi

    return 0
}

test_duplicate_config_key_fails() {
    local temp_dir
    local config_file

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    config_file="$temp_dir/config.conf"

    cat >"$config_file" <<'EOF'
distro_profile=ubuntu
distro_profile=debian
EOF

    LWBS_USER_CONFIG_PATH_OVERRIDE="$config_file"

    if load_user_config >/dev/null 2>&1; then
        printf 'Duplicate configuration setting was accepted.\n' >&2
        return 1
    fi

    return 0
}

test_unsupported_distro_config_fails() {
    local temp_dir
    local config_file

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    config_file="$temp_dir/config.conf"

    printf '%s\n' \
        'distro_profile=gentoo' \
        >"$config_file"

    LWBS_USER_CONFIG_PATH_OVERRIDE="$config_file"

    if load_user_config >/dev/null 2>&1; then
        printf 'Unsupported distribution profile was accepted.\n' >&2
        return 1
    fi

    return 0
}

test_config_is_not_executed() {
    local temp_dir
    local config_file
    local marker

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    config_file="$temp_dir/config.conf"
    marker="$temp_dir/executed"

    cat >"$config_file" <<EOF
distro_profile=\$(touch "$marker")
EOF

    LWBS_USER_CONFIG_PATH_OVERRIDE="$config_file"

    if load_user_config >/dev/null 2>&1; then
        printf 'Invalid command-like configuration value was accepted.\n' >&2
        return 1
    fi

    assert_not_exists \
        "$marker" \
        "user configuration was executed as shell code"
}

run_test \
    "use repository defaults when user configuration is absent" \
    test_missing_config_uses_defaults

run_test \
    "load a valid user configuration override" \
    test_valid_config_override

run_test \
    "reject unsupported configuration settings" \
    test_invalid_config_key_fails

run_test \
    "reject duplicate configuration settings" \
    test_duplicate_config_key_fails

run_test \
    "reject unsupported distro configuration" \
    test_unsupported_distro_config_fails

run_test \
    "parse user configuration as data rather than shell code" \
    test_config_is_not_executed

finish_tests