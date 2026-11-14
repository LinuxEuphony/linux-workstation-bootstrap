#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Security tooling.
#
# Provides broadly useful defensive host and device security utilities used
# across supported workstation profiles.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# USBGuard is installed but its daemon is intentionally not activated here.
# A reviewed USB authorization policy must exist before enforcement is enabled
# to avoid unexpectedly blocking legitimate workstation devices.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "security-tools"
}

module_name() {
    printf '%s\n' "Security Tools"
}

module_description() {
    printf '%s\n' \
        "Defensive host and USB device security utilities."
}

module_capabilities() {
    printf '%s\n' \
        "host-intrusion-protection" \
        "usb-device-control"
}

module_services() {
    printf '%s\n' \
        "fail2ban.service enabled active never"
}

# Verify that the expected security commands are available after package
# installation. Service-state verification remains handled by the managed
# service lifecycle framework.
module_verify() {
    local command_name
    local verification_failed=false

    local -a required_commands=(
        "fail2ban-client"
        "usbguard"
    )

    for command_name in "${required_commands[@]}"; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required security command is unavailable: %s\n' \
            "$command_name" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}