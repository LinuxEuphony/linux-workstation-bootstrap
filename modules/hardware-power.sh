#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Hardware and power management.
#
# Selects hardware-specific workstation capabilities only when relevant
# hardware is detected. This avoids installing or configuring support for
# devices that are not present on the target workstation.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "hardware-power"
}

module_name() {
    printf '%s\n' "Hardware and Power Management"
}

module_description() {
    printf '%s\n' \
        "Hardware support, device diagnostics, and power-management utilities."
}

module_capabilities() {
    if hardware_has_storage_health_candidate; then
        printf '%s\n' "storage-health-tools"
    fi

    if hardware_has_power_management; then
        printf '%s\n' "power-diagnostics"
    fi

    if hardware_has_bluetooth_adapter; then
        printf '%s\n' "bluetooth-stack"
    fi

    if hardware_has_video_device; then
        printf '%s\n' "video-device-tools"
    fi

    if hardware_has_fingerprint_reader; then
        printf '%s\n' "fingerprint-tools"
    fi
}

module_services() {
    if hardware_has_bluetooth_adapter; then
        printf '%s\n' \
            "bluetooth.service enabled active never"
    fi
}

module_verify() {
    local command_name
    local verification_failed=false

    local -a required_commands=()

    if hardware_has_storage_health_candidate; then
        required_commands+=("smartctl")
    fi

    if hardware_has_power_management; then
        required_commands+=("powertop")
    fi

    if hardware_has_bluetooth_adapter; then
        required_commands+=("bluetoothctl")
    fi

    if hardware_has_video_device; then
        required_commands+=("v4l2-ctl")
    fi

    if hardware_has_fingerprint_reader; then
        required_commands+=("fprintd-list")
    fi

    for command_name in "${required_commands[@]}"; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required hardware command is unavailable: %s\n' \
            "$command_name" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}
