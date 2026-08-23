# Linux Workstation Bootstrap

A reusable, distro-aware Linux workstation bootstrap utility for preparing and configuring Linux workstations in a
consistent and controlled way.

Linux Workstation Bootstrap detects the host operating system and architecture, identifies the appropriate distribution
family and package manager, and allows the user to confirm or select the distribution profile before configuration
begins.

## Features

* Automatic Linux distribution detection using `/etc/os-release`
* Distribution version and codename detection
* Architecture detection and normalization
* Distribution-family identification
* Package-manager identification
* Interactive distribution profile confirmation and selection
* Persistent per-run logging
* Clear separation between platform detection, user interaction, core logic, and distribution-specific behavior

Initial distribution profiles include:

* Ubuntu
* Debian
* Kali Linux

## Requirements

* Linux
* Bash
* A distribution providing `/etc/os-release`

The bootstrap is intended to be run from a terminal.

## Clone

Clone the repository:

```bash
git clone https://github.com/LinuxEuphony/linux-workstation-bootstrap.git
```

Enter the project directory:

```bash
cd linux-workstation-bootstrap
```

Make the bootstrap executable:

```bash
chmod +x bin/linux-workstation-bootstrap
```

## Run

Start the bootstrap:

```bash
./bin/linux-workstation-bootstrap
```

The application detects the current system and presents the detected configuration before proceeding.

Example:

```text
Detected system

  Distribution : Ubuntu 26.04 LTS
  ID           : ubuntu
  Version      : 26.04
  Codename     : resolute
  Architecture : amd64
  Family       : debian
  Package mgr  : apt

Use the detected Ubuntu profile? [Y/n]
```

If the detected profile is not selected, a supported distribution profile can be chosen manually.

## Logging

Each execution creates a dedicated session log.

By default, logs are stored under:

```text
~/.local/state/linux-workstation-bootstrap/logs/
```

If `XDG_STATE_HOME` is configured, that location is used instead.

The bootstrap displays both the current session log and the log directory when it runs.

## Project Structure

```text
linux-workstation-bootstrap/
├── bin/
│   └── linux-workstation-bootstrap
├── lib/
│   ├── bootstrap.sh
│   ├── core.sh
│   ├── detect.sh
│   ├── logging.sh
│   └── ui.sh
├── distros/
├── modules/
├── profiles/
├── tests/
└── docs/
```

The command in `bin/` is the application entry point. Shared application behavior lives under `lib/`, while
distribution-specific behavior, installation modules, and workstation profiles are kept separate as the project grows.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Distribution detection, user confirmation, logging, validation, and execution behavior are kept separate so that system
operations can be validated before changes are applied.

Review the selected configuration and installation actions before allowing system-level changes to proceed.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.
