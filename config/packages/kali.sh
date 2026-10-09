#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Kali Linux package capability mappings.
#
# Capability identifiers are portable workstation intents.
# Values are the Kali Linux package names that satisfy those capabilities.
#
# A capability may map to multiple packages by separating package names
# with newlines.

LWBS_CAPABILITY_PACKAGES=(
    [curl]="curl"
    [dos2unix]="dos2unix"
    [figlet]="figlet"
    [nano]="nano"
    [sed]="sed"
    [wget]="wget"
    [xz]="xz-utils"
)