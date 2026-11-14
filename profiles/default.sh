#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Default workstation profile.
#
# Defines a practical general-purpose workstation baseline while leaving
# development, container, database, and security-specialized tooling to
# dedicated profiles or explicit module selection.
#
# Profile contract functions are loaded and invoked indirectly by the shared
# profile framework.
# shellcheck disable=SC2317,SC2329

profile_id() {
    printf '%s\n' "default"
}

profile_name() {
    printf '%s\n' "Default Workstation"
}

profile_description() {
    printf '%s\n' \
        "General-purpose workstation utilities, desktop applications, and hardware support."
}

profile_modules() {
    printf '%s\n' \
        "common-utilities" \
        "desktop-media" \
        "hardware-power"
}
