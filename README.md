# Linux Workstation Bootstrap

A reusable, distro-aware Linux workstation bootstrap utility for preparing and configuring Linux workstations in a
consistent and controlled way.

Linux Workstation Bootstrap detects the host operating system and architecture, identifies the distribution family and
package manager, and allows the user to confirm or select the distribution profile before configuration begins.

## Features

* Linux distribution detection using `/etc/os-release`
* Distribution version and codename detection
* Architecture detection and normalization
* Distribution-family identification
* Package-manager identification
* Interactive distribution profile confirmation and selection
* Command-line distribution profile override
* Dry-run execution mode
* Persistent per-session logging
* Centralized application configuration
* Separate core, detection, logging, CLI and user-interface layers

Supported distribution profiles:

* Ubuntu
* Debian
* Kali Linux

## Requirements

* Linux
* Bash 5 or newer
* `/etc/os-release`

## Clone and Run

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

Run the bootstrap:

```bash
./bin/linux-workstation-bootstrap
```

The detected system configuration is displayed before a distribution profile is selected.

## Usage

```text
./bin/linux-workstation-bootstrap [options]
```

Available options:

```text
--distro <profile>   Use a specific distribution profile
--dry-run            Preview actions without applying system changes
-y, --yes            Accept a supported detected profile without prompting
--version            Display the application version
-h, --help           Display help
```

Examples:

```bash
./bin/linux-workstation-bootstrap --help
```

```bash
./bin/linux-workstation-bootstrap --version
```

```bash
./bin/linux-workstation-bootstrap --dry-run --yes
```

```bash
./bin/linux-workstation-bootstrap --distro debian --dry-run
```

Selecting a different distribution profile does not alter the detected host information. The bootstrap keeps the
detected system and selected configuration profile separate.

## Logging

Each bootstrap execution creates a dedicated session log.

By default, logs are stored under:

```text
~/.local/state/linux-workstation-bootstrap/logs/
```

If `XDG_STATE_HOME` is configured, it is used as the state directory instead.

The bootstrap displays the current session log and log directory during execution.

## Project Structure

```text
linux-workstation-bootstrap/
├── bin/
│   └── linux-workstation-bootstrap
├── config/
│   └── defaults.sh
├── lib/
│   ├── arguments.sh
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

Application defaults and platform mappings are centralized under `config/`. Shared application behavior is kept under
`lib/`, while distribution-specific behavior, installation modules and workstation profiles are kept separate.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Host detection, profile selection, configuration, logging and execution logic are separated so that operations can be
validated before system changes are applied. Dry-run mode provides a way to preview execution without applying changes.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.
