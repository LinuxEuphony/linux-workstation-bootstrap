#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Database tools.
#
# Provides database client utilities used across supported workstation
# profiles without implicitly installing or managing database servers.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "database-tools"
}

module_name() {
    printf '%s\n' "Database Tools"
}

module_description() {
    printf '%s\n' \
        "Database client and administration utilities for workstation use."
}

module_capabilities() {
    printf '%s\n' \
        "postgresql-client"
}

# Verify that the expected PostgreSQL client commands are available after
# installation. Database server state is intentionally outside this module.
module_verify() {
    local command_name
    local verification_failed=false

    local -a required_commands=(
        "psql"
        "pg_dump"
        "pg_restore"
    )

    for command_name in "${required_commands[@]}"; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required database command is unavailable: %s\n' \
            "$command_name" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}
