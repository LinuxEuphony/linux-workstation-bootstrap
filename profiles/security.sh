#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Security workstation profile.
#
# Combines general workstation utilities, development tooling, and defensive
# security capabilities without coupling the profile to Kali Linux or
# implicitly installing specialized offensive security tooling.
#
# Additional specialist capabilities can be added explicitly through the CLI
# as the security module catalog grows.
#
# Profile contract functions are loaded and invoked indirectly by the shared
# profile framework.
# shellcheck disable=SC2317,SC2329

profile_id() {
    printf '%s\n' "security"
}

profile_name() {
    printf '%s\n' "Security Workstation"
}

profile_description() {
    printf '%s\n' \
        "Security engineering workstation with defensive security and development tooling."
}

profile_modules() {
    printf '%s\n' \
        "common-utilities" \
        "development-tools" \
        "security-tools"
}
