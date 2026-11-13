#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Containers and virtualization.
#
# Provides container runtime tooling and core VMware guest integration used
# across supported workstation profiles.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "containers-virtualization"
}

module_name() {
    printf '%s\n' "Containers and Virtualization"
}

module_description() {
    printf '%s\n' \
        "Container runtime and core virtualization guest tooling."
}

module_capabilities() {
    printf '%s\n' \
        "docker-engine" \
        "vmware-guest-tools"
}

# Verify that the expected container and virtualization commands are
# available after installation. Service state and user-group membership are
# handled separately by their dedicated frameworks.
module_verify() {
    local command_name
    local verification_failed=false

    local -a required_commands=(
        "docker"
        "vmtoolsd"
    )

    for command_name in "${required_commands[@]}"; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required container or virtualization command is unavailable: %s\n' \
            "$command_name" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}
