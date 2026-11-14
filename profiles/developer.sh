#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Developer workstation profile.
#
# Combines the reusable modules required for a practical software engineering
# workstation without embedding distribution-specific package names or
# installation behavior.
#
# Desktop/media, security, and hardware-specific modules remain optional and
# can be added explicitly through the CLI.
#
# Profile contract functions are loaded and invoked indirectly by the shared
# profile framework.
# shellcheck disable=SC2317,SC2329

profile_id() {
    printf '%s\n' "developer"
}

profile_name() {
    printf '%s\n' "Developer Workstation"
}

profile_description() {
    printf '%s\n' \
        "Software engineering workstation with development, container, and database tooling."
}

profile_modules() {
    printf '%s\n' \
        "common-utilities" \
        "development-tools" \
        "containers-virtualization" \
        "database-tools"
}
