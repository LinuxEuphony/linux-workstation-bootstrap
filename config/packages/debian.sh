#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Debian package capability mappings.
#
# Capability identifiers are portable workstation intents.
# Values are the Debian package names that satisfy those capabilities.
#
# A capability may map to multiple packages by separating package names
# with newlines.

declare -gA LWBS_CAPABILITY_PACKAGES=(
    ["bison"]="bison"
    ["build-toolchain"]="build-essential"
    ["calibre"]="calibre"
    ["cloc"]="cloc"
    ["cmake"]="cmake"
    ["curl"]="curl"
    ["darktable"]="darktable"
    ["docker-engine"]="docker.io"
    ["dos2unix"]="dos2unix"
    ["ffmpeg"]="ffmpeg"
    ["figlet"]="figlet"
    ["flex"]="flex"
    ["gimp"]="gimp"
    ["git"]="git"
    ["inkscape"]="inkscape"
    ["nano"]="nano"
    ["pavucontrol"]="pavucontrol"
    ["pkg-config"]="pkg-config"
    ["postgresql-client"]="postgresql-client"
    ["scons"]="scons"
    ["sed"]="sed"
    ["sox"]="sox"
    ["swig"]="swig"
    ["vlc"]="vlc"
    ["vmware-guest-tools"]="open-vm-tools"
    ["wget"]="wget"
    ["xz"]="xz-utils"
)
