#!/usr/bin/env bash

set -uo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"

# shellcheck source=./testlib.sh
source "$TEST_DIR/testlib.sh"

LWBS_ROOT="$REPO_ROOT"

# Source the complete bootstrap framework because these tests exercise
# hardware-aware capability and service planning.
# shellcheck source=../lib/bootstrap.sh
source "$REPO_ROOT/lib/bootstrap.sh"

create_hardware_test_profile() {
    local profile_directory="${1:-}"
    local profile_id="${2:-}"

    mkdir -p -- "$profile_directory"

    cat >"$profile_directory/$profile_id.sh" <<EOF_PROFILE
profile_id() {
    printf '%s\n' "$profile_id"
}

profile_name() {
    printf '%s\n' "Hardware Test Profile"
}

profile_description() {
    printf '%s\n' "Selects the hardware and power management module."
}

profile_modules() {
    printf '%s\n' "hardware-power"
}
EOF_PROFILE
}

test_detect_hardware_from_controlled_fixtures() {
    local temp_dir
    local sysfs_root
    local device_root

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    sysfs_root="$temp_dir/sys"
    device_root="$temp_dir/dev"

    mkdir -p \
        "$sysfs_root/class/bluetooth/hci0" \
        "$sysfs_root/class/block/nvme0n1" \
        "$sysfs_root/class/power_supply/BAT0" \
        "$sysfs_root/bus/usb/devices/1-1" \
        "$device_root"

    touch "$device_root/video0"

    printf '%s\n' \
        "Example Fingerprint Sensor" \
        >"$sysfs_root/bus/usb/devices/1-1/product"

    LWBS_SYSFS_ROOT_OVERRIDE="$sysfs_root"
    LWBS_DEVICE_ROOT_OVERRIDE="$device_root"

    hardware_has_bluetooth_adapter
    hardware_has_video_device
    hardware_has_fingerprint_reader
    hardware_has_storage_health_candidate
    hardware_has_power_management
}

test_absent_hardware_is_not_detected() {
    local temp_dir
    local sysfs_root
    local device_root

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    sysfs_root="$temp_dir/sys"
    device_root="$temp_dir/dev"

    mkdir -p \
        "$sysfs_root/class/bluetooth" \
        "$sysfs_root/class/block" \
        "$sysfs_root/class/power_supply" \
        "$sysfs_root/class/powercap" \
        "$sysfs_root/devices/system/cpu/cpufreq" \
        "$sysfs_root/bus/usb/devices" \
        "$sysfs_root/class/input" \
        "$device_root"

    LWBS_SYSFS_ROOT_OVERRIDE="$sysfs_root"
    LWBS_DEVICE_ROOT_OVERRIDE="$device_root"

    if hardware_has_bluetooth_adapter; then
        printf 'Bluetooth hardware was detected unexpectedly.\n' >&2
        return 1
    fi

    if hardware_has_video_device; then
        printf 'Video hardware was detected unexpectedly.\n' >&2
        return 1
    fi

    if hardware_has_fingerprint_reader; then
        printf 'Fingerprint hardware was detected unexpectedly.\n' >&2
        return 1
    fi

    if hardware_has_storage_health_candidate; then
        printf 'Storage health hardware was detected unexpectedly.\n' >&2
        return 1
    fi

    if hardware_has_power_management; then
        printf 'Power-management hardware was detected unexpectedly.\n' >&2
        return 1
    fi
}

test_hardware_module_can_be_noop() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 1
    }

    load_module hardware-power

    assert_equal \
        "hardware-power" \
        "$LWBS_MODULE_ID"

    assert_equal \
        "Hardware and Power Management" \
        "$LWBS_MODULE_NAME"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_CAPABILITIES[@]}"

    assert_equal \
        "0" \
        "${#LWBS_MODULE_SERVICES[@]}"

    reset_module_contract
}

test_hardware_module_selects_detected_capabilities() {
    local temp_dir
    local capabilities

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 0
    }

    load_module hardware-power

    capabilities="$(
        printf '%s\n' "${LWBS_MODULE_CAPABILITIES[@]}"
    )"

    assert_equal \
        $'storage-health-tools\npower-diagnostics\nbluetooth-stack\nvideo-device-tools\nfingerprint-tools' \
        "$capabilities"

    assert_equal \
        "1" \
        "${#LWBS_MODULE_SERVICES[@]}"

    assert_equal \
        "bluetooth.service enabled active never" \
        "${LWBS_MODULE_SERVICES[0]}"

    reset_module_contract
}

test_hardware_capabilities_resolve_on_supported_distros() {
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
            storage-health-tools \
            power-diagnostics \
            bluetooth-stack \
            video-device-tools \
            fingerprint-tools

        resolved="$(
            printf '%s\n' "${resolved_packages[@]}"
        )"

        assert_equal \
            $'smartmontools\npowertop\nbluez\nv4l-utils\nfprintd' \
            "$resolved" \
            "hardware capability mapping differs for $distro"

        reset_capability_map
    done
}

test_hardware_verification_succeeds() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 0
    }

    load_module hardware-power

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        return 0
    }

    module_verify

    reset_module_contract
}

test_hardware_verification_detects_missing_command() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 1
    }

    load_module hardware-power

    # shellcheck disable=SC2317,SC2329
    command_exists() {
        local command_name="${1:-}"

        [[ "$command_name" != "powertop" ]]
    }

    if module_verify >/dev/null 2>&1; then
        printf 'module_verify accepted a missing power diagnostic command.\n' >&2
        return 1
    fi

    reset_module_contract
}

test_hardware_module_can_be_selected_by_profile() {
    local temp_dir
    local profile_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"

    create_hardware_test_profile \
        "$profile_dir" \
        "hardware-test-profile"

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 1
    }

    load_profile hardware-test-profile

    assert_equal \
        "hardware-test-profile" \
        "$LWBS_PROFILE_ID"

    assert_equal \
        "1" \
        "${#LWBS_PROFILE_MODULES[@]}"

    assert_equal \
        "hardware-power" \
        "${LWBS_PROFILE_MODULES[0]}"

    reset_profile_contract
}

test_no_hardware_produces_no_install_actions() {
    local temp_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/execution-plan.out"

    create_hardware_test_profile \
        "$profile_dir" \
        "hardware-empty-profile"

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 1
    }

    run_profile hardware-empty-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "0" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "0" \
        "$LWBS_PLAN_SERVICE_ACTION_COUNT"

    assert_contains \
        "$output" \
        "Hardware and Power Management"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

test_detected_hardware_produces_complete_plan() {
    local temp_dir
    local profile_dir
    local output_file
    local output

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    profile_dir="$temp_dir/profiles"
    output_file="$temp_dir/execution-plan.out"

    create_hardware_test_profile \
        "$profile_dir" \
        "hardware-full-profile"

    LWBS_PROFILES_DIR_OVERRIDE="$profile_dir"

    DISTRO_ADAPTER_PROFILE="ubuntu"

    load_capability_map ubuntu

    LWBS_DRY_RUN=true
    LWBS_ASSUME_YES=false

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    distro_package_state() {
        printf '%s\n' "absent"
    }

    # BlueZ is not available until its planned package installation.
    # shellcheck disable=SC2317,SC2329
    service_manager_available() {
        return 0
    }

    # shellcheck disable=SC2317,SC2329
    query_service_presence() {
        printf '%s\n' "absent"
    }

    run_profile hardware-full-profile >"$output_file"

    output="$(<"$output_file")"

    assert_equal \
        "previewed" \
        "$LWBS_PLAN_STATUS"

    assert_equal \
        "5" \
        "$LWBS_PLAN_INSTALL_ACTION_COUNT"

    assert_equal \
        "1" \
        "$LWBS_PLAN_SERVICE_ACTION_COUNT"

    assert_contains \
        "$output" \
        "smartmontools [install]"

    assert_contains \
        "$output" \
        "powertop [install]"

    assert_contains \
        "$output" \
        "bluez [install]"

    assert_contains \
        "$output" \
        "v4l-utils [install]"

    assert_contains \
        "$output" \
        "fprintd [install]"

    assert_contains \
        "$output" \
        "bluetooth.service [configure after install: enabled=enabled active=active]"

    assert_contains \
        "$output" \
        "Dry-run mode: execution plan was not applied."
}

test_bluetooth_service_is_not_declared_without_adapter() {
    local temp_dir

    temp_dir="$(make_test_temp_dir)"
    register_test_cleanup "$temp_dir"

    setup_test_logging "$temp_dir"

    # shellcheck disable=SC2317,SC2329
    hardware_has_storage_health_candidate() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_power_management() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_bluetooth_adapter() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_video_device() {
        return 1
    }

    # shellcheck disable=SC2317,SC2329
    hardware_has_fingerprint_reader() {
        return 1
    }

    load_module hardware-power

    assert_equal \
        "0" \
        "${#LWBS_MODULE_SERVICES[@]}"

    reset_module_contract
}

run_test \
    "detect relevant hardware from controlled fixtures" \
    test_detect_hardware_from_controlled_fixtures

run_test \
    "ignore hardware that is not present" \
    test_absent_hardware_is_not_detected

run_test \
    "allow the hardware module to become a no-op" \
    test_hardware_module_can_be_noop

run_test \
    "select capabilities for detected hardware" \
    test_hardware_module_selects_detected_capabilities

run_test \
    "resolve hardware capabilities on all supported distros" \
    test_hardware_capabilities_resolve_on_supported_distros

run_test \
    "verify available hardware utilities" \
    test_hardware_verification_succeeds

run_test \
    "detect a missing hardware utility during verification" \
    test_hardware_verification_detects_missing_command

run_test \
    "select hardware support through a workstation profile" \
    test_hardware_module_can_be_selected_by_profile

run_test \
    "avoid installation when applicable hardware is absent" \
    test_no_hardware_produces_no_install_actions

run_test \
    "build a complete plan for detected hardware" \
    test_detected_hardware_produces_complete_plan

run_test \
    "avoid Bluetooth service management without an adapter" \
    test_bluetooth_service_is_not_declared_without_adapter

finish_tests
