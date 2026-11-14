#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Hardware detection utilities.
#
# Provides read-only hardware discovery used by workstation modules when
# deciding whether hardware-specific capabilities should be included.
#
# These functions are a sourced library API and may be invoked indirectly by
# dynamically loaded workstation modules.
# shellcheck disable=SC2317,SC2329

hardware_has_bluetooth_adapter() {
    local sysfs_root="${LWBS_SYSFS_ROOT_OVERRIDE:-/sys}"
    local device_path

    for device_path in "$sysfs_root"/class/bluetooth/hci*; do
        if [[ -e "$device_path" ]]; then
            return 0
        fi
    done

    return 1
}

hardware_has_video_device() {
    local device_root="${LWBS_DEVICE_ROOT_OVERRIDE:-/dev}"
    local device_path

    for device_path in "$device_root"/video*; do
        if [[ -e "$device_path" ]]; then
            return 0
        fi
    done

    return 1
}

hardware_has_fingerprint_reader() {
    local sysfs_root="${LWBS_SYSFS_ROOT_OVERRIDE:-/sys}"
    local descriptor_path
    local descriptor_value
    local normalized_value

    for descriptor_path in \
        "$sysfs_root"/bus/usb/devices/*/product \
        "$sysfs_root"/class/input/*/device/name; do

        if [[ ! -r "$descriptor_path" ]]; then
            continue
        fi

        if IFS= read -r descriptor_value <"$descriptor_path"; then
            :
        else
            continue
        fi

        normalized_value="${descriptor_value,,}"

        if [[ "$normalized_value" == *fingerprint* ||
            "$normalized_value" == *fprint* ||
            "$normalized_value" == *wbdi* ]]; then

            return 0
        fi
    done

    return 1
}

hardware_has_storage_health_candidate() {
    local sysfs_root="${LWBS_SYSFS_ROOT_OVERRIDE:-/sys}"
    local device_path

    for device_path in \
        "$sysfs_root"/class/block/sd* \
        "$sysfs_root"/class/block/nvme*; do

        if [[ -e "$device_path" ]]; then
            return 0
        fi
    done

    return 1
}

hardware_has_power_management() {
    local sysfs_root="${LWBS_SYSFS_ROOT_OVERRIDE:-/sys}"
    local device_path

    for device_path in "$sysfs_root"/class/power_supply/BAT*; do
        if [[ -e "$device_path" ]]; then
            return 0
        fi
    done

    for device_path in "$sysfs_root"/class/powercap/*; do
        if [[ -e "$device_path" ]]; then
            return 0
        fi
    done

    for device_path in "$sysfs_root"/devices/system/cpu/cpufreq/policy*; do
        if [[ -e "$device_path" ]]; then
            return 0
        fi
    done

    return 1
}
