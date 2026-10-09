#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Default application configuration.
# This file:
# 1. Defines application identity and version information.
# 2. Defines runtime requirements.
# 3. Defines supported distribution profiles.
# 4. Defines distribution, package manager, and architecture mappings.
# 5. Defines user-configuration defaults and locations.
# 6. Defines persistent logging defaults.

# Application identity.
readonly LWBS_APP_NAME="Linux Workstation Bootstrap"
readonly LWBS_APP_SLUG="linux-workstation-bootstrap"
readonly LWBS_VERSION="0.1.0-dev"

# Minimum supported Bash major version.
readonly LWBS_MIN_BASH_MAJOR=5

# Default source of Linux distribution information.
readonly LWBS_OS_RELEASE_PATH="/etc/os-release"

# Supported distribution profiles.
declare -ar LWBS_SUPPORTED_DISTROS=(
    "ubuntu"
    "debian"
    "kali"
)

# Human-readable names for supported distribution profiles.
declare -Ar LWBS_DISTRO_DISPLAY_NAMES=(
    [ubuntu]="Ubuntu"
    [debian]="Debian"
    [kali]="Kali Linux"
)

# Default distribution selection behaviour.
#
# "auto" means the bootstrap should use normal host detection and
# confirmation rather than forcing a specific distribution profile.
readonly LWBS_DEFAULT_DISTRO_PROFILE="auto"

# User configuration location.
#
# The actual root is resolved from XDG_CONFIG_HOME or ~/.config at runtime.
readonly LWBS_CONFIG_DIRECTORY_NAME="$LWBS_APP_SLUG"
readonly LWBS_CONFIG_FILE_NAME="config.conf"

# Distribution-to-family mappings.
# Additional distributions may be detected even when they do not yet
# have an installation profile supported by the application.
declare -Ar LWBS_DISTRO_FAMILIES=(
    [ubuntu]="debian"
    [debian]="debian"
    [kali]="debian"
    [linuxmint]="debian"
    [pop]="debian"
    [elementary]="debian"

    [fedora]="rpm"
    [rhel]="rpm"
    [rocky]="rpm"
    [almalinux]="rpm"
    [centos]="rpm"

    [arch]="arch"
    [manjaro]="arch"
    [endeavouros]="arch"

    [opensuse-leap]="suse"
    [opensuse-tumbleweed]="suse"
    [sles]="suse"
)

# Default package manager for each distribution family.
declare -Ar LWBS_FAMILY_PACKAGE_MANAGERS=(
    [debian]="apt"
    [rpm]="dnf"
    [arch]="pacman"
    [suse]="zypper"
)

# Normalize common architecture names used by Linux distributions.
declare -Ar LWBS_ARCH_ALIASES=(
    [x86_64]="amd64"
    [aarch64]="arm64"
    [arm64]="arm64"
    [armv7l]="armhf"
    [i386]="i386"
    [i486]="i386"
    [i586]="i386"
    [i686]="i386"
)

# Persistent logging configuration.
readonly LWBS_LOG_DIRECTORY_NAME="logs"
readonly LWBS_LOG_FILE_PREFIX="run"

# Permissions applied to application state and log files.
readonly LWBS_STATE_DIR_MODE="700"
readonly LWBS_LOG_DIR_MODE="700"
readonly LWBS_LOG_FILE_MODE="600"