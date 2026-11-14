#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Desktop and media applications.
#
# Provides broadly useful graphical, image, audio, and video applications
# used across supported workstation profiles.
#
# Distribution-specific package names remain in config/packages rather than
# in this module.
#
# Module contract functions are loaded and invoked indirectly by the shared
# module framework.
# shellcheck disable=SC2317,SC2329

module_id() {
    printf '%s\n' "desktop-media"
}

module_name() {
    printf '%s\n' "Desktop and Media"
}

module_description() {
    printf '%s\n' \
        "Graphical, image, audio, and video applications for workstation use."
}

module_capabilities() {
    printf '%s\n' \
        "gimp" \
        "inkscape" \
        "vlc" \
        "ffmpeg" \
        "sox" \
        "darktable" \
        "calibre" \
        "pavucontrol"
}

# Verify that the expected desktop and media commands are available after
# installation. Package-state verification remains handled by the execution
# framework.
module_verify() {
    local command_name
    local verification_failed=false

    local -a required_commands=(
        "gimp"
        "inkscape"
        "vlc"
        "ffmpeg"
        "sox"
        "darktable"
        "calibre"
        "pavucontrol"
    )

    for command_name in "${required_commands[@]}"; do
        if command_exists "$command_name"; then
            continue
        fi

        printf 'Error: required desktop or media command is unavailable: %s\n' \
            "$command_name" >&2

        verification_failed=true
    done

    if "$verification_failed"; then
        return 1
    fi

    return 0
}
