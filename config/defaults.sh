#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Default application configuration.

readonly LWBS_APP_NAME="Linux Workstation Bootstrap"
readonly LWBS_APP_SLUG="linux-workstation-bootstrap"
readonly LWBS_VERSION_FILE_NAME="VERSION"

readonly LWBS_MIN_BASH_MAJOR=5

readonly LWBS_OS_RELEASE_PATH="/etc/os-release"

declare -ar LWBS_SUPPORTED_DISTROS=(
    "ubuntu"
    "debian"
    "kali"
)

declare -Ar LWBS_DISTRO_DISPLAY_NAMES=(
    ["ubuntu"]="Ubuntu"
    ["debian"]="Debian"
    ["kali"]="Kali Linux"
)

declare -Ar LWBS_DISTRO_SUPPORTED_ARCHITECTURES=(
    ["ubuntu"]="amd64 arm64"
    ["debian"]="amd64 arm64"
    ["kali"]="amd64 arm64"
)

readonly LWBS_DEFAULT_DISTRO_PROFILE="auto"
readonly LWBS_DEFAULT_WORKSTATION_PROFILE="default"

readonly LWBS_CONFIG_DIRECTORY_NAME="$LWBS_APP_SLUG"
readonly LWBS_CONFIG_FILE_NAME="config.conf"

declare -Ar LWBS_DISTRO_FAMILIES=(
    ["ubuntu"]="debian"
    ["debian"]="debian"
    ["kali"]="debian"
    ["linuxmint"]="debian"
    ["pop"]="debian"
    ["elementary"]="debian"

    ["fedora"]="rpm"
    ["rhel"]="rpm"
    ["rocky"]="rpm"
    ["almalinux"]="rpm"
    ["centos"]="rpm"

    ["arch"]="arch"
    ["manjaro"]="arch"
    ["endeavouros"]="arch"

    ["opensuse-leap"]="suse"
    ["opensuse-tumbleweed"]="suse"
    ["sles"]="suse"
)

declare -Ar LWBS_FAMILY_PACKAGE_MANAGERS=(
    ["debian"]="apt"
    ["rpm"]="dnf"
    ["arch"]="pacman"
    ["suse"]="zypper"
)

declare -Ar LWBS_ARCH_ALIASES=(
    ["x86_64"]="amd64"
    ["aarch64"]="arm64"
    ["arm64"]="arm64"
    ["armv7l"]="armhf"
    ["i386"]="i386"
    ["i486"]="i386"
    ["i586"]="i386"
    ["i686"]="i386"
)

readonly LWBS_LOG_DIRECTORY_NAME="logs"
readonly LWBS_LOG_FILE_PREFIX="run"

readonly LWBS_RECOVERY_DIRECTORY_NAME="recovery"
readonly LWBS_RECOVERY_ACTIVE_FILE_NAME="active.state"
readonly LWBS_RECOVERY_LAST_FILE_NAME="last-run.state"

readonly LWBS_LOCK_DIRECTORY_NAME="execution.lock"
readonly LWBS_LOCK_METADATA_FILE_NAME="owner.state"

readonly LWBS_STATE_DIR_MODE="700"
readonly LWBS_LOG_DIR_MODE="700"
readonly LWBS_LOG_FILE_MODE="600"
readonly LWBS_RECOVERY_DIR_MODE="700"
readonly LWBS_RECOVERY_FILE_MODE="600"
readonly LWBS_LOCK_DIR_MODE="700"
readonly LWBS_LOCK_FILE_MODE="600"
