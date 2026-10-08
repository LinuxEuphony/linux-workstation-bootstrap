# Workstation Software Inventory

This document records and classifies the workstation software, system configuration, package-management operations, and installation methods represented by the legacy workstation bootstrap script.

It is the migration source of truth for moving the legacy setup into the modular Linux Workstation Bootstrap architecture.

Nothing listed here is installed merely because it appears in this inventory.

## Purpose

The legacy workstation script mixed several concerns in one execution path:

- operating-system preparation
- package-management configuration
- desktop environment setup
- workstation utilities
- development dependencies
- container tooling
- databases
- security tooling
- media applications
- hardware support
- power management
- external repositories
- service management
- user and group changes

The new architecture separates these concerns into reusable modules and distribution-specific implementations.

Every legacy item is therefore classified before it is migrated.

## Classification

Items use the following primary classifications:

| Classification | Meaning |
| --- | --- |
| Common workstation | General-purpose tools useful across workstation profiles |
| Development | Compilers, libraries, IDEs, language tooling, and build tools |
| Containers and virtualization | Container engines, runtimes, and virtual-machine integration |
| Database | Database servers, clients, and development packages |
| Security | Security, encryption, access-control, monitoring, and hardening tools |
| Desktop and media | Desktop environment, graphical applications, audio, video, imaging, and productivity software |
| Hardware and power management | Hardware interfaces, printing, Bluetooth, storage health, input devices, fingerprint, and power tooling |
| Distro-specific | Operating-system or distribution-specific package/configuration behavior |
| Optional | Software that should not be installed by every workstation profile |
| External installation | Software requiring a repository, download, language package manager, or other installation path outside normal distro packages |
| Obsolete or unsupported | Invalid, retired, superseded, or unsuitable legacy entries |

An item may have a primary classification and additional migration considerations.

## Migration Status

The inventory uses these dispositions:

| Disposition | Meaning |
| --- | --- |
| Keep | Suitable for migration into an appropriate module |
| Optional | Preserve, but only through explicit profile/module selection |
| External | Preserve through the external software installation framework |
| Map | Requires package-name or distro-specific capability mapping |
| Review | Preserve in the inventory until current distro support is verified |
| Replace | Preserve the original intent using a corrected/current implementation |
| Remove | Do not migrate the legacy implementation; rationale is recorded |

---

# System and Package Management

| Item / Operation | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `usermod -a -G lpadmin root` | Hardware and power management | Replace | Printer administration intent should use managed user/group support rather than modifying `root`. |
| `apt-listbugs` | Distro-specific | Review | Debian-family package-management helper. Availability and usefulness vary by supported distro. |
| `apt-get-transport-https` | Obsolete or unsupported | Replace | Legacy entry appears to intend `apt-transport-https`. Modern APT has native HTTPS support, so this should not become a normal workstation dependency. |
| `dpkg` | Distro-specific | Keep | Base Debian-family package tooling. Usually already present. |
| `dpkg-dev` | Development | Keep | Debian package development tooling. |
| `devscripts` | Development | Optional | Debian package-maintenance/development tooling. |
| `swig` | Development | Keep | Build/interface-generation tool. |
| `libboost-all-dev` | Development | Keep | Boost development bundle. |
| `libboost-system-dev` | Development | Review | Potentially redundant when `libboost-all-dev` is installed. |
| `libboost-thread-dev` | Development | Review | Potentially redundant when `libboost-all-dev` is installed. |
| `libboost-program-options-dev` | Development | Review | Potentially redundant when `libboost-all-dev` is installed. |
| `libboost-test-dev` | Development | Review | Potentially redundant when `libboost-all-dev` is installed. |
| `libeigen3-dev` | Development | Keep | C++ linear algebra development library. |
| `zlib1g-dev` | Development | Keep | Compression development library. |
| `libbz2-dev` | Development | Keep | bzip2 development library. |
| `liblzma-dev` | Development | Keep | XZ/LZMA development library. |
| `cmake` | Development | Keep | Appears more than once in the legacy script. Migrate once. |
| `dpkg --add-architecture i386` | Distro-specific | Optional | Multiarch changes must only occur when a selected capability actually requires 32-bit packages. |
| `apt-get update` | Distro-specific | Replace | Already represented by the distro adapter contract. |
| `apt-get upgrade -y` | Distro-specific | Review | System upgrade is distinct from workstation package installation and must not happen implicitly. |
| `apt-get dist-upgrade -y` | Distro-specific | Review | Potentially disruptive system upgrade operation. Must not run implicitly. |
| `apt-get full-upgrade -y` | Distro-specific | Review | Potentially disruptive system upgrade operation. Must not run implicitly. |
| `apt-get-file` | Obsolete or unsupported | Replace | Legacy package name is incorrect. Original intent is the APT file-search capability, normally provided by `apt-file`. |
| `apt-getitude` | Obsolete or unsupported | Replace | Legacy package name is incorrect. Original intent appears to be `aptitude`. |
| `linux-headers-$(uname -r)` | Development | Map | Runtime kernel header requirement. Must resolve dynamically. |
| `linux-headers-amd64` | Distro-specific | Map | Architecture and distro-specific kernel-header meta-package. |

---

# Desktop Environment

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `kali-desktop-gnome` | Distro-specific | Optional | Kali-specific GNOME desktop meta-package. Must never be requested by Ubuntu or Debian modules. |
| `gnome-core` | Desktop and media | Optional | Desktop environment capability. |
| `alacarte` | Desktop and media | Optional | GNOME menu editor. |
| `libxml2-dev` | Development | Keep | Development library rather than a desktop application despite its original placement. |

---

# Audio and Media Playback

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `alsa-utils` | Hardware and power management | Keep | ALSA audio hardware utilities. |
| `pavucontrol` | Desktop and media | Optional | Graphical audio control. |
| `audacious` | Desktop and media | Optional | Audio player. |
| `vlc` | Desktop and media | Optional | Media player. |
| `sox` | Desktop and media | Optional | Audio conversion and processing. |

---

# Spotify

| Item / Operation | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| Spotify signing key download | External installation | External | External repository bootstrap. |
| Spotify APT repository | External installation | External | Must use managed repository configuration rather than inline shell commands. |
| `spotify-client` | Desktop and media | External | Installed from an external vendor repository. |
| Legacy `/etc/apt/trusted.gpg.d/` key handling | External installation | Replace | Repository signing configuration should use a dedicated managed keyring. |
| Legacy HTTP repository URL | External installation | Replace | Current external repository configuration must be verified before implementation. |

---

# Files, Text, Archives, and Productivity

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `calibre` | Desktop and media | Optional | E-book management. |
| `okular` | Desktop and media | Optional | Document viewer. |
| `gedit` | Desktop and media | Optional | Graphical text editor. |
| `leafpad` | Desktop and media | Review | Legacy lightweight editor. Verify current distro availability before migration. |
| `nano` | Common workstation | Keep | Terminal text editor. |
| `shotwell` | Desktop and media | Optional | Photo manager. |
| `zipalign` | Development | Optional | Primarily Android/archive alignment tooling. |
| `handbrake` | Desktop and media | Optional | Video transcoding. |
| `dos2unix` | Common workstation | Keep | Line-ending conversion utility. |
| `xz-utils` | Common workstation | Keep | Appears more than once in the legacy script. Migrate once. |

---

# Design and Imaging

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `gimp` | Desktop and media | Optional | Image editing. |
| `akira` | Desktop and media | Review | Verify current support and installation source before migration. |
| `inkscape` | Desktop and media | Optional | Vector graphics editor. |
| `darktable` | Desktop and media | Optional | Photography workflow. |
| `imagemagick` | Desktop and media | Keep | Image manipulation tooling. |

---

# Development Tools

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `build-essential` | Development | Keep | Core compiler/build toolchain. |
| `codeblocks` | Development | Optional | IDE. |
| `bless` | Development | Optional | Hex editor. |
| `sed` | Common workstation | Keep | Core text-processing utility. Normally already installed. |
| `anjuta` | Development | Review | Legacy GNOME IDE. Verify current support before migration. |
| `geany` | Development | Optional | Lightweight editor/IDE. |
| `git` | Development | Keep | Source control. |
| `php-mbstring` | Development | Optional | PHP extension. |
| `php-xml` | Development | Optional | PHP XML extension. |
| `cloc` | Development | Keep | Source-code statistics. |
| `python2` | Obsolete or unsupported | Remove | Python 2 is end-of-life and should not be part of the default modern workstation. |
| `python3` | Development | Keep | Current Python runtime. |
| `python-gobject` | Development | Map | Package naming/version support must be resolved for current distributions. |
| `libfontconfig1-dev` | Development | Keep | Fontconfig development headers. |
| `libbsd-dev` | Development | Keep | BSD compatibility development library. |
| `libcairo2-dev` | Development | Keep | Cairo development headers. |
| `libxcursor-dev` | Development | Keep | X11 cursor development library. |
| `libxrandr-dev` | Development | Keep | XRandR development library. |
| `libxkbfile-dev` | Development | Keep | XKB development library. |
| `libgif-dev` | Development | Keep | GIF development library. |
| `libtiff5-dev` | Development | Replace | Version-specific legacy package name. Resolve to the current TIFF development capability. |
| `libfreetype6-dev` | Development | Keep | Appears twice in the legacy script. Migrate once. |
| `libavresample-dev` | Obsolete or unsupported | Replace | Legacy FFmpeg/Libav component. Do not preserve the package blindly. |
| `libdbus-1-dev` | Development | Keep | D-Bus development headers. |
| `libssl-dev` | Development | Keep | OpenSSL development headers. |
| `libglu1-mesa-dev` | Development | Keep | OpenGL/GLU development library. |
| `libgl1-mesa-dev` | Development | Map | OpenGL development capability may require current distro-specific package mapping. |
| `libegl1-mesa-dev` | Development | Map | EGL development capability may require current distro-specific package mapping. |
| `libavformat-dev` | Development | Keep | FFmpeg format development headers. |
| `libavcodec-dev` | Development | Keep | FFmpeg codec development headers. |
| `libpulse-dev` | Development | Keep | PulseAudio development headers. |
| `figlet` | Common workstation | Optional | Terminal banner utility. |
| `fakeroot` | Development | Keep | Package/build environment helper. |
| `libglew-dev` | Development | Keep | OpenGL extension development library. |
| `libsdl2-dev` | Development | Keep | SDL2 development library. |
| `libsdl2-image-dev` | Development | Keep | SDL2 image development library. |
| `libglm-dev` | Development | Keep | OpenGL mathematics library. |
| `freeglut3-dev` | Development | Map | OpenGL/GLUT development capability. Verify current package mapping. |
| `npm` | Development | Keep | JavaScript package manager/runtime tooling dependency. |
| `swi-prolog` | Development | Optional | Prolog development environment. |
| `clang-9` | Obsolete or unsupported | Replace | Pinned legacy compiler version. Resolve to an appropriate supported Clang capability instead of preserving version 9. |
| `bison` | Development | Keep | Parser generator. |
| `flex` | Development | Keep | Lexical analyzer generator. |
| `libfuse-dev` | Development | Map | FUSE development package naming differs across current releases. |
| `libudev-dev` | Development | Keep | udev development headers. |
| `pkg-config` | Development | Keep | Build dependency metadata utility. |
| `libc6-dev-i386` | Development | Optional | 32-bit development support. Requires multiarch use case. |
| `libcap2-bin` | Security | Keep | Linux capabilities utilities. |
| `scons` | Development | Optional | Build system. |

---

# Bash Language Server

| Item / Operation | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `bash-language-server` | Development | External | Installed with `npm -g`, not the distro package manager. |
| `npm i -g bash-language-server` | External installation | External | Must eventually use the external software installation framework. |

---

# FFmpeg

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `ffmpeg` | Desktop and media | Keep | Media processing capability. |
| `libavformat-dev` | Development | Keep | Development component. |
| `libavcodec-dev` | Development | Keep | Development component. |
| `libavresample-dev` | Obsolete or unsupported | Replace | Legacy component retained in inventory only for migration traceability. |

---

# Containers and Virtualization

## Docker

The legacy script contains two competing Docker installation strategies.

| Item / Operation | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `docker.io` | Containers and virtualization | Review | Distribution-provided Docker package. |
| `systemctl enable docker --now` | Containers and virtualization | Replace | Service lifecycle must eventually use the managed service framework. |
| `usermod -aG docker $USER` | Containers and virtualization | Replace | Group membership must eventually use managed user/group support. |
| Docker upstream repository | External installation | External | Required only if upstream Docker CE is selected. |
| Hard-coded Debian `bookworm` Docker repository | Distro-specific | Remove | Must not be reused across Ubuntu, Debian, and Kali. |
| Docker GPG key installation | External installation | External | Must use verified managed repository/key handling. |
| `docker-ce` | Containers and virtualization | External | Upstream Docker package. |
| `docker-ce-cli` | Containers and virtualization | External | Upstream Docker CLI. |
| `containerd.io` | Containers and virtualization | External | Upstream container runtime package. |

The final implementation must choose a deliberate Docker installation policy instead of installing both `docker.io` and upstream Docker CE.

## VMware Guest Integration

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `open-vm-tools` | Containers and virtualization | Optional | VMware guest integration. |
| `open-vm-tools-desktop` | Containers and virtualization | Optional | Graphical VMware guest integration. |

---

# Database

| Item / Operation | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `postgresql` | Database | Keep | PostgreSQL server. |
| `postgresql-contrib` | Database | Keep | PostgreSQL contributed extensions. |
| `postgresql-server-dev-all` | Database | Optional | PostgreSQL server development headers. |
| `systemctl enable postgresql` | Database | Replace | Service lifecycle should eventually use managed service support. |
| `systemctl start postgresql` | Database | Replace | Service lifecycle should eventually use managed service support. |
| `systemctl status postgresql` | Database | Replace | Verification belongs in the post-install verification layer. |

---

# Package Management Applications

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `synaptic` | Desktop and media | Optional | Graphical Debian-family package manager. |
| `gdebi` | Distro-specific | Optional | Debian package installer. |
| `npm` | Development | Keep | Listed here in the legacy script but classified as development tooling. |
| `cmake` | Development | Keep | Duplicate legacy declaration. Migrate once. |

---

# Internet and Network Utilities

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `wget` | Common workstation | Keep | Network download utility. |
| `curl` | Common workstation | Keep | Network transfer utility. |
| `speedtest-cli` | Common workstation | Optional | Network throughput utility. |
| `surf` | Desktop and media | Optional | Lightweight graphical browser. |
| `putty` | Common workstation | Optional | SSH/Telnet client tools. |
| `certbot` | Security | Optional | ACME certificate tooling. |

---

# Legacy Optional Internet Applications

These entries were commented out in the source script. They remain accounted for but must not become default dependencies.

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `qbittorrent` | Desktop and media | Optional | BitTorrent client. |
| `thunderbird` | Desktop and media | Optional | Mail client. |
| `tor` | Security | Optional | Tor service/client. |
| `apt-get-transport-tor` | Security | Review | Legacy APT-over-Tor capability. Verify support before considering migration. |
| `torbrowser-launcher` | Security | Optional | Tor Browser bootstrap utility. |
| `falkon` | Desktop and media | Optional | Browser. |
| `midori` | Desktop and media | Review | Verify current distro support before migration. |

---

# Wine and Windows Compatibility

These entries were commented out in the legacy script.

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `wine:i386` | Desktop and media | Optional | Requires i386 architecture support. |
| `wine32` | Desktop and media | Optional | 32-bit Wine capability. |
| `playonlinux` | Desktop and media | Review | Preserve intent but verify whether it remains an appropriate supported frontend. |

---

# Bluetooth

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `bluez` | Hardware and power management | Keep | Linux Bluetooth stack. |
| `bluez-utils` | Hardware and power management | Map | Package availability/naming must be checked per supported distribution. |
| `bluetooth` | Hardware and power management | Map | Debian-family Bluetooth meta/service package behavior varies. |
| `blueman` | Hardware and power management | Optional | Graphical Bluetooth manager. |

---

# Video and Input Hardware

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `v4l-utils` | Hardware and power management | Keep | Video4Linux device utilities. |
| `xinput` | Hardware and power management | Optional | X11 input device configuration utility. |

---

# Printing

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `cups` | Hardware and power management | Optional | Printing service. |
| `cups-client` | Hardware and power management | Optional | Printing client utilities. |
| `lpadmin` group membership | Hardware and power management | Replace | Must use managed user/group membership rather than modifying `root`. |

---

# Desktop Configuration

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `grub-customizer` | Desktop and media | Review | Verify current distro availability and whether direct bootloader customization belongs in workstation bootstrap. |
| `paprefs` | Desktop and media | Optional | Audio preferences. |
| `dconf-editor` | Desktop and media | Optional | GNOME configuration editor. |
| `seahorse-nautilus` | Desktop and media | Optional | File-manager integration for keys/encryption. |
| `snapd` | Distro-specific | Optional | Packaging platform. Must not be assumed across every supported distro/profile. |
| `systemctl enable --now snapd apparmor` | Distro-specific | Replace | Two different services are coupled in one legacy command. Service management must be explicit and capability-driven. |

---

# Security and Monitoring

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `fail2ban` | Security | Optional | Brute-force protection. |
| `stacer` | Security | Review | System monitoring/management application. Verify current support. |
| `snort` | Security | Optional | Network intrusion detection. |
| `usbguard` | Security | Optional | USB device access control. |
| `libcryptsetup-dev` | Security | Optional | cryptsetup development library. |
| `bruteforce-luks` | Security | Optional | Security-testing tool. Should belong only to an explicit security profile. |
| `libcap2-bin` | Security | Keep | Linux capability management utilities. |
| `apparmor` service enablement | Security | Review | Security framework management should be distro-aware and must not be implicitly enabled merely because Snap is installed. |

---

# Screen Recording and Desktop Utilities

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `obs-studio` | Desktop and media | Optional | Screen recording and streaming. |
| `pomodoro` | Desktop and media | Review | Verify current package availability before migration. |

---

# Fingerprint Support

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `fprintd` | Hardware and power management | Optional | Fingerprint daemon. |
| `libpam-fprintd` | Hardware and power management | Optional | PAM fingerprint integration. |
| `fprint-demo` | Hardware and power management | Review | Legacy/demo package. Verify current availability before migration. |
| `imagemagick` | Desktop and media | Keep | Was grouped with fingerprint packages in the legacy script but belongs to image tooling. |

---

# Storage Health

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `smartmontools` | Hardware and power management | Keep | SMART disk-health tools. |

---

# Power and System Protection

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `molly-guard` | Hardware and power management | Optional | Protects against accidental shutdown/reboot. |
| `bfh-container` | Distro-specific | Review | Preserve until package purpose and supported-distro availability are verified. |
| `pm-utils` | Hardware and power management | Review | Legacy power-management tooling. Modern systems may use other mechanisms. |
| `progress-linux-container` | Distro-specific | Review | Distribution-specific/niche container package. Verify applicability before migration. |

---

# Other Development Libraries and Tools

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `libncurses5-dev` | Development | Map | Version-specific legacy development package. Resolve current ncurses development capability. |
| `libfuse-dev` | Development | Map | Resolve current FUSE development package per distro/release. |
| `libudev-dev` | Development | Keep | udev development headers. |
| `pkg-config` | Development | Keep | Build metadata tool. |
| `libc6-dev-i386` | Development | Optional | 32-bit development support. |
| `scons` | Development | Optional | Build automation. |

---

# Commented Legacy Item

| Item | Classification | Disposition | Notes |
| --- | --- | --- | --- |
| `education-logic-games` | Optional | Optional | Was disabled in the original script. Preserve only as historical optional intent. |

---

# Known Follow-up Requirements

The following requirements were identified after the original script and must be included in the migration inventory rather than added ad hoc to unrelated modules.

## HEIF / HEIC Image Support

| Item | Classification | Disposition | Intended Module |
| --- | --- | --- | --- |
| `libheif-examples` | Desktop and media | Map | Desktop/media |
| `libheif-plugin-libde265` | Desktop and media | Map | Desktop/media |
| `libheif-plugins-all` | Desktop and media | Map | Desktop/media |

These packages represent one **HEIF/HEIC image support capability**. They should be resolved together and may require distro/version-specific mappings.

## GTK Compatibility

| Item | Classification | Disposition | Intended Module |
| --- | --- | --- | --- |
| `libgtk2.0-0t64` | Distro-specific | Map | Capability-dependent |

The `t64` package name is release-specific and must not become a portable module package name.

## PeaZip

| Item | Classification | Disposition | Intended Module |
| --- | --- | --- | --- |
| PeaZip | Desktop and media | External | Desktop/media |

PeaZip should be treated as external software unless a suitable supported distro package is deliberately selected.

---

# Duplicate Entries

The legacy script contains several duplicate or overlapping requirements.

| Duplicate / Conflict | Migration Decision |
| --- | --- |
| `cmake` appears in the initial development dependency group and again under package management | Declare once in the development capability. |
| `xz-utils` appears more than once | Declare once in common workstation utilities. |
| `libfreetype6-dev` appears in both general development and OpenGL dependency groups | Resolve once even if multiple capabilities depend on it. Dependency resolution should deduplicate it. |
| `docker.io` and upstream `docker-ce` are both installed | Select one Docker installation strategy. Do not install both blindly. |
| `apt-get upgrade`, `dist-upgrade`, and `full-upgrade` are all invoked sequentially | Do not reproduce this sequence. System upgrades require a separate explicit policy. |
| `ffmpeg` and FFmpeg development libraries are mixed together | Runtime/media capability and development headers should be separable. |
| `imagemagick` is grouped with fingerprint packages | Move to desktop/media imaging. |
| `npm` appears under package-management concerns while also supporting development tooling | Treat as development tooling. |

---

# Invalid or Legacy Package Names

The following entries must not be copied directly into new modules.

| Legacy Entry | Migration Treatment |
| --- | --- |
| `apt-get-transport-https` | Do not preserve blindly. Original HTTPS transport intent is obsolete for modern APT. |
| `apt-get-file` | Replace with the intended/current APT file-search capability. |
| `apt-getitude` | Replace with the intended `aptitude` capability if retained. |
| `python2` | Remove from normal workstation profiles. |
| `clang-9` | Replace with a supported compiler capability instead of pinning version 9. |
| `libtiff5-dev` | Resolve to the current TIFF development capability. |
| `libavresample-dev` | Do not preserve as a package dependency. Resolve the modern FFmpeg requirement. |
| `libncurses5-dev` | Resolve through distro/version-specific package mapping. |
| `libgtk2.0-0t64` | Treat as version-specific mapping, not a universal package name. |

Items marked `Review` elsewhere in this document remain intentionally unresolved until their current availability and purpose are assessed. They are not silently discarded.

---

# External Installation Inventory

These installations must eventually use the external software installation framework rather than normal distro package handling.

| Software | Legacy Method | Future Handling |
| --- | --- | --- |
| Spotify | Vendor APT repository and signing key | Managed external repository installation |
| Docker CE | Docker vendor repository and signing key | Managed external repository installation |
| Bash Language Server | Global NPM installation | Managed external package-manager installation |
| PeaZip | Known follow-up application | Verified external package/download mechanism |

Download integrity, repository signing, and installer verification are handled by the dedicated external installation and integrity work rather than duplicated inside individual modules.

---

# Service Lifecycle Operations

The legacy script directly manages services:

```text
docker
postgresql
snapd
apparmor
```

These operations must not simply be copied into module scripts.

They should eventually use the managed service lifecycle framework so service state changes participate in:

- dry-run
- logging
- execution planning
- verification
- failure handling

---

# User and Group Changes

The legacy script directly modifies:

```text
lpadmin
docker
```

Group membership must eventually use managed user/group support.

Modules should express the required membership rather than executing `usermod` directly.

---

# Architecture Changes

The following legacy operations are architecture-specific:

```text
dpkg --add-architecture i386
libc6-dev-i386
wine:i386
wine32
linux-headers-amd64
```

These cannot be unconditional workstation requirements.

Architecture changes must be driven by capabilities that actually need them.

---

# Proposed Module Migration Map

The inventory maps naturally into the focused module work already planned.

## Common Workstation Utilities

Candidate responsibilities:

```text
nano
sed
dos2unix
xz-utils
wget
curl
speedtest-cli
figlet
```

Package-manager internals such as `dpkg` are distro infrastructure rather than normal user-facing module requirements.

## Development Tools

Candidate responsibilities include:

```text
build-essential
git
cmake
swig
Boost development libraries
Eigen
compression development libraries
PHP development/runtime extensions
Python 3
C/C++ graphics libraries
FFmpeg development libraries
OpenSSL development libraries
D-Bus development libraries
Clang capability
Bison
Flex
FUSE development
udev development
pkg-config
SCons
Bash Language Server
optional IDE/editor tooling
```

## Containers and Virtualization

Candidate responsibilities:

```text
Docker
containerd
Docker service lifecycle
Docker group membership
open-vm-tools
open-vm-tools-desktop
```

Docker installation policy must be resolved before implementation.

## Database Tools

Candidate responsibilities:

```text
postgresql
postgresql-contrib
postgresql-server-dev-all
PostgreSQL service lifecycle
```

## Security Tooling

Candidate responsibilities:

```text
fail2ban
snort
usbguard
certbot
libcap2-bin
cryptsetup development tooling
bruteforce-luks
optional Tor tooling
AppArmor-related requirements
```

Security-testing tools must remain opt-in rather than appearing in a generic default workstation profile.

## Desktop and Media Applications

Candidate responsibilities include:

```text
GNOME components
audio applications
VLC
SoX
Spotify
Calibre
Okular
graphical editors
Shotwell
HandBrake
GIMP
Inkscape
FFmpeg
Synaptic
GDebi
browsers
OBS Studio
Darktable
HEIF/HEIC support
PeaZip
```

Large desktop applications should remain optional where appropriate.

## Hardware and Power Management

Candidate responsibilities:

```text
ALSA utilities
Bluetooth
Video4Linux
CUPS
fingerprint support
xinput
smartmontools
molly-guard
power-management tooling
```

---

# Items That Must Not Become Normal Module Package Lists

The following are infrastructure or workflow concerns rather than ordinary packages to place directly into capability modules:

```text
apt-get update
apt-get upgrade
apt-get dist-upgrade
apt-get full-upgrade
dpkg --add-architecture i386
external repository creation
repository signing-key installation
systemctl enable/start commands
usermod group changes
hard-coded distro repository URLs
```

These belong to shared infrastructure, explicit configuration operations, or dedicated framework capabilities.

---

# Migration Rules

When module implementation begins:

1. Do not copy legacy package commands directly into modules.
2. Modules express workstation capability intent.
3. Distribution adapters remain responsible for package-manager execution.
4. Package names that differ by distro or release are resolved through package mapping.
5. External software uses the external installation framework.
6. Service state changes use managed service lifecycle support.
7. User/group changes use managed membership support.
8. Architecture changes are capability-driven.
9. Optional software remains opt-in.
10. Obsolete entries retain their migration rationale in this inventory rather than disappearing silently.
11. Duplicate package requirements are declared where logically appropriate and deduplicated during resolution.
12. A package being present in this inventory does not imply inclusion in the default workstation profile.

---

# Inventory Outcome

The legacy workstation setup has been decomposed into:

- common workstation utilities
- development tooling and libraries
- containers and virtualization
- database tooling
- security tooling
- desktop and media applications
- hardware and power management
- distro-specific operations
- optional software
- external installations
- obsolete or superseded requirements

The inventory is now suitable for implementing focused workstation modules without carrying forward the monolithic behavior of the legacy script.