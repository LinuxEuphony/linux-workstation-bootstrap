#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Fedora package capability mappings.
#
# Capability identifiers are portable workstation intents.
# Values are Fedora package names that satisfy those capabilities.
#
# A capability may map to multiple packages by separating package names
# with newlines.
#
# The mappings prefer packages provided by Fedora repositories. External
# repositories remain the responsibility of the external installer framework.

declare -gA LWBS_CAPABILITY_PACKAGES=(
    ["bison"]="bison"
    ["bluetooth-stack"]="bluez"
    ["build-toolchain"]=$'gcc\ngcc-c++\nmake'
    ["calibre"]="calibre"
    ["cloc"]="cloc"
    ["cmake"]="cmake"
    ["curl"]="curl"
    ["darktable"]="darktable"
    ["docker-engine"]="moby-engine"
    ["dos2unix"]="dos2unix"
    ["ffmpeg"]="ffmpeg-free"
    ["figlet"]="figlet"
    ["fingerprint-tools"]="fprintd"
    ["flex"]="flex"
    ["gimp"]="gimp"
    ["git"]="git"
    ["host-intrusion-protection"]="fail2ban"
    ["inkscape"]="inkscape"
    ["nano"]="nano"
    ["pavucontrol"]="pavucontrol"
    ["pkg-config"]="pkgconf-pkg-config"
    ["postgresql-client"]="postgresql"
    ["power-diagnostics"]="powertop"
    ["scons"]="scons"
    ["sed"]="sed"
    ["sox"]="sox"
    ["storage-health-tools"]="smartmontools"
    ["swig"]="swig"
    ["usb-device-control"]="usbguard"
    ["video-device-tools"]="v4l-utils"
    ["vlc"]="vlc"
    ["vmware-guest-tools"]="open-vm-tools"
    ["wget"]="wget"
    ["xz"]="xz"
)
