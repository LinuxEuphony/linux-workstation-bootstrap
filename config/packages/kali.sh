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

declare -gA LWBS_CAPABILITY_PACKAGES=(
    ["bison"]="bison"
    ["build-toolchain"]="build-essential"
    ["cloc"]="cloc"
    ["cmake"]="cmake"
    ["curl"]="curl"
    ["docker-engine"]="docker.io"
    ["dos2unix"]="dos2unix"
    ["figlet"]="figlet"
    ["flex"]="flex"
    ["git"]="git"
    ["nano"]="nano"
    ["pkg-config"]="pkg-config"
    ["postgresql-client"]="postgresql-client"
    ["scons"]="scons"
    ["sed"]="sed"
    ["swig"]="swig"
    ["vmware-guest-tools"]="open-vm-tools"
    ["wget"]="wget"
    ["xz"]="xz-utils"
)
