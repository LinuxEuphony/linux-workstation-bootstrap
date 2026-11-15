#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

prepare_configuration_test() {
    local temp_dir="${1:-}"

    setup_test_logging "$temp_dir"

    LWBS_DRY_RUN=false

    reset_execution_plan
    reset_execution_results
}

test_parse_valid_configuration_requirement() {
    local temp_dir
    local source_file
    local configuration_id
    local kind
    local scope
    local destination
    local source
    local mode
    local backup

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    printf '%s\n' "value=true" >"$source_file"

    parse_configuration_requirement \
        "example|file|user|$temp_dir/destination.conf|$source_file|0644|backup" \
        configuration_id \
        kind \
        scope \
        destination \
        source \
        mode \
        backup

    assert_equal "example" "$configuration_id"
    assert_equal "file" "$kind"
    assert_equal "user" "$scope"
    assert_equal "$temp_dir/destination.conf" "$destination"
    assert_equal "$source_file" "$source"
    assert_equal "0644" "$mode"
    assert_equal "backup" "$backup"
}

test_reject_invalid_configuration_requirement() {
    local temp_dir
    local source_file
    local configuration_id
    local kind
    local scope
    local destination
    local source
    local mode
    local backup

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    printf '%s\n' "value=true" >"$source_file"

    if parse_configuration_requirement \
        "example|invalid|user|$temp_dir/destination.conf|$source_file|0644|backup" \
        configuration_id \
        kind \
        scope \
        destination \
        source \
        mode \
        backup \
        >/dev/null 2>&1; then

        printf 'Invalid configuration requirement was accepted.\n' >&2
        return 1
    fi
}

test_detect_create_update_and_skip_states() {
    local temp_dir
    local source_file
    local destination
    local state

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"

    printf '%s\n' "value=true" >"$source_file"

    state="$(
        configuration_state \
            file \
            example \
            "$destination" \
            "$source_file" \
            0644
    )"

    assert_equal "create" "$state"

    printf '%s\n' "value=false" >"$destination"
    chmod 0644 "$destination"

    state="$(
        configuration_state \
            file \
            example \
            "$destination" \
            "$source_file" \
            0644
    )"

    assert_equal "update" "$state"

    cp "$source_file" "$destination"
    chmod 0644 "$destination"

    state="$(
        configuration_state \
            file \
            example \
            "$destination" \
            "$source_file" \
            0644
    )"

    assert_equal "skip" "$state"
}

test_detect_mode_only_change() {
    local temp_dir
    local source_file
    local destination
    local state

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"

    printf '%s\n' "value=true" >"$source_file"
    cp "$source_file" "$destination"
    chmod 0600 "$destination"

    state="$(
        configuration_state \
            file \
            example \
            "$destination" \
            "$source_file" \
            0644
    )"

    assert_equal "update" "$state"
}

test_apply_user_managed_file_idempotently() {
    local temp_dir
    local source_file
    local destination
    local configuration_key
    local state

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"

    printf '%s\n' "value=true" >"$source_file"

    LWBS_MODULE_CONFIGURATIONS=(
        "example|file|user|$destination|$source_file|0644|no-backup"
    )

    plan_module_configurations sample

    configuration_key="$(
        configuration_plan_key \
            sample \
            example
    )"

    assert_equal \
        "create" \
        "${LWBS_PLAN_CONFIGURATION_ACTION[$configuration_key]}"

    execute_planned_configuration_actions sample

    assert_equal \
        "$(cat "$source_file")" \
        "$(cat "$destination")"

    state="$(
        configuration_state \
            file \
            example \
            "$destination" \
            "$source_file" \
            0644
    )"

    assert_equal "skip" "$state"
}

test_create_backup_before_update() {
    local temp_dir
    local source_file
    local destination
    local backup_count

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"

    printf '%s\n' "new-value=true" >"$source_file"
    printf '%s\n' "old-value=true" >"$destination"
    chmod 0644 "$destination"

    LWBS_MODULE_CONFIGURATIONS=(
        "example|file|user|$destination|$source_file|0644|backup"
    )

    plan_module_configurations sample
    execute_planned_configuration_actions sample

    backup_count="$(
        find "$temp_dir" \
            -maxdepth 1 \
            -type f \
            -name 'destination.conf.lwbs-backup.*' |
            wc -l
    )"

    assert_equal "1" "$backup_count"
}

test_managed_block_preserves_unmanaged_content() {
    local temp_dir
    local source_file
    local destination
    local rendered

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"

    cat >"$source_file" <<'EOF'
managed=true
another=value
EOF

    cat >"$destination" <<'EOF'
before=true

# >>> linux-workstation-bootstrap:example >>>
old=value
# <<< linux-workstation-bootstrap:example <<<

after=true
EOF

    chmod 0644 "$destination"

    LWBS_MODULE_CONFIGURATIONS=(
        "example|block|user|$destination|$source_file|0644|no-backup"
    )

    plan_module_configurations sample
    execute_planned_configuration_actions sample

    rendered="$(cat "$destination")"

    assert_contains "$rendered" "before=true"
    assert_contains "$rendered" "managed=true"
    assert_contains "$rendered" "another=value"
    assert_contains "$rendered" "after=true"

    if [[ "$rendered" == *"old=value"* ]]; then
        printf 'Old managed block content remained after replacement.\n' >&2
        return 1
    fi
}

test_system_configuration_uses_privileged_execution() {
    local temp_dir
    local source_file
    local destination
    local marker

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/system.conf"
    marker="$temp_dir/privileged-used"

    printf '%s\n' "value=true" >"$source_file"

    # shellcheck disable=SC2317,SC2329
    run_privileged_command() {
        touch "$marker"
        "$@"
    }

    LWBS_MODULE_CONFIGURATIONS=(
        "example|file|system|$destination|$source_file|0644|no-backup"
    )

    plan_module_configurations sample
    execute_planned_configuration_actions sample

    if [[ ! -f "$marker" ]]; then
        printf 'System configuration bypassed privileged execution.\n' >&2
        return 1
    fi
}

test_configuration_change_counts_as_module_change() {
    local temp_dir
    local source_file
    local destination

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"

    printf '%s\n' "value=true" >"$source_file"

    LWBS_MODULE_CONFIGURATIONS=(
        "example|file|user|$destination|$source_file|0644|no-backup"
    )

    plan_module_configurations sample

    if ! module_has_planned_configuration_changes sample; then
        printf 'Managed configuration change was not detected.\n' >&2
        return 1
    fi
}

test_configuration_contents_are_not_logged() {
    local temp_dir
    local source_file
    local destination
    local secret_value
    local log_contents

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    prepare_configuration_test "$temp_dir"

    source_file="$temp_dir/source.conf"
    destination="$temp_dir/destination.conf"
    secret_value="super-secret-configuration-value"

    printf '%s\n' "$secret_value" >"$source_file"

    LWBS_MODULE_CONFIGURATIONS=(
        "example|file|user|$destination|$source_file|0600|no-backup"
    )

    plan_module_configurations sample
    execute_planned_configuration_actions sample

    log_contents="$(cat "$LWBS_LOG_FILE")"

    if [[ "$log_contents" == *"$secret_value"* ]]; then
        printf 'Sensitive configuration value was written to the session log.\n' >&2
        return 1
    fi
}

run_test \
    "parse a valid managed configuration requirement" \
    test_parse_valid_configuration_requirement

run_test \
    "reject an invalid managed configuration requirement" \
    test_reject_invalid_configuration_requirement

run_test \
    "detect create, update, and satisfied configuration states" \
    test_detect_create_update_and_skip_states

run_test \
    "detect configuration permission-only changes" \
    test_detect_mode_only_change

run_test \
    "apply a user managed file idempotently" \
    test_apply_user_managed_file_idempotently

run_test \
    "create a backup before updating an existing configuration" \
    test_create_backup_before_update

run_test \
    "replace only the owned section of a managed block" \
    test_managed_block_preserves_unmanaged_content

run_test \
    "route system configuration through privileged execution" \
    test_system_configuration_uses_privileged_execution

run_test \
    "treat configuration changes as module changes" \
    test_configuration_change_counts_as_module_change

run_test \
    "avoid logging sensitive configuration contents" \
    test_configuration_contents_are_not_logged

finish_tests
