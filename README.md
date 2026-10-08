# Linux Workstation Bootstrap

A reusable, distro-aware Linux workstation bootstrap utility for preparing and configuring Linux workstations in a consistent and controlled way.

Linux Workstation Bootstrap is being built as a modular replacement for a single large workstation setup script. It separates host detection, command execution, distribution-specific behavior, installable capabilities, and workstation profiles so that each concern can evolve independently.

## Current Capabilities

The current bootstrap foundation provides:

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
* Controlled command execution
* Centralized privileged command execution
* Distribution adapter loading and contract validation
* Ubuntu package-management adapter
* Ubuntu package index refresh support
* Ubuntu package installation support

Configured distribution profiles:

* Ubuntu
* Debian
* Kali Linux

Current adapter implementation status:

| Profile | Adapter |
| --- | --- |
| Ubuntu | Implemented |
| Debian | Pending |
| Kali Linux | Pending |

## Architecture

The project is intentionally split into layers rather than placing detection, package installation, prompts, and system changes in one script.

```text
User
  │
  ▼
bin/linux-workstation-bootstrap
  │
  ▼
lib/bootstrap.sh
  │
  ├── config/defaults.sh
  ├── lib/arguments.sh
  ├── lib/core.sh
  ├── lib/detect.sh
  ├── lib/logging.sh
  ├── lib/ui.sh
  ├── lib/execution.sh
  └── lib/distro.sh
          │
          ▼
     distros/<profile>.sh
          │
          ▼
        modules/
          │
          ▼
        profiles/
```

The main architectural responsibilities are:

* **Entry point**: `bin/linux-workstation-bootstrap` establishes safe Bash behavior, resolves the repository root, and hands control to `bootstrap_main`.
* **Bootstrap orchestration**: `lib/bootstrap.sh` coordinates the application lifecycle. It decides the order of operations without containing distro-specific package commands.
* **Configuration**: `config/defaults.sh` contains built-in application defaults, supported distro mappings, architecture mappings, and logging defaults.
* **CLI parsing**: `lib/arguments.sh` interprets command-line options and records the requested runtime behavior.
* **Core utilities**: `lib/core.sh` provides distro-independent runtime checks and reusable helpers.
* **System detection**: `lib/detect.sh` determines the actual host distribution, distro family, architecture, and expected package manager.
* **Logging**: `lib/logging.sh` creates and writes the per-run session log.
* **Terminal UI**: `lib/ui.sh` owns human-facing output, prompts, menus, help, and version display.
* **Execution boundary**: `lib/execution.sh` centralizes command execution, privilege escalation, dry-run handling, and command result logging.
* **Distro adapter framework**: `lib/distro.sh` loads the selected distro adapter and verifies that it implements the required contract.
* **Distribution adapters**: `distros/` contains operating-system-specific package-management implementations.
* **Modules**: `modules/` contains reusable workstation capabilities such as development tools, containers, databases, desktop/media tooling, security tooling, and hardware support.
* **Profiles**: `profiles/` selects groups of modules to form complete workstation configurations.

The key separation is:

```text
Profiles decide which capabilities are wanted.
Modules define what those capabilities require.
Distribution adapters implement how the operating system satisfies them.
Shared libraries provide the infrastructure used by all of them.
```

The detected host and selected distribution profile are intentionally separate. Detection records what the machine actually is, while profile selection determines which supported distro behavior the bootstrap should use.

## Bootstrap Flow

The bootstrap lifecycle currently begins with:

```text
Parse CLI arguments
       │
       ▼
Initialize logging
       │
       ▼
Validate runtime
       │
       ▼
Detect host system
       │
       ▼
Select distribution profile
       │
       ▼
Load distribution adapter
       │
       ▼
Validate adapter environment
```

As the project evolves, the lifecycle continues into:

```text
Resolve profiles and modules
       │
       ▼
Build execution plan
       │
       ▼
Apply changes
       │
       ▼
Verify and summarize
```

Loading a distribution adapter does not itself update repositories or install packages. Package operations are invoked explicitly by higher-level bootstrap actions and modules.

## Distribution Adapter Contract

`lib/distro.sh` provides a common interface between shared bootstrap logic and distribution-specific behavior.

Every distribution adapter must implement:

```text
distro_validate_environment
distro_update_package_index
distro_install_packages
```

The first concrete implementation is:

```text
distros/ubuntu.sh
```

The Ubuntu adapter:

* validates that the detected system belongs to the Debian package-management family
* validates that APT is the expected package manager
* verifies that `apt-get` is available
* refreshes package indexes through the shared privileged execution layer
* installs one or more packages through the shared privileged execution layer
* inherits dry-run behavior from the shared execution utilities

Shared application code does not execute `apt-get` directly.

## Requirements

* Linux
* Bash 5 or newer
* `/etc/os-release`

Ubuntu package operations additionally require:

* APT
* `apt-get`

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

The detected system configuration is displayed before a distribution profile is selected and its adapter is loaded.

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
./bin/linux-workstation-bootstrap --distro ubuntu --dry-run
```

Selecting a different distribution profile does not alter the detected host information. The bootstrap keeps the detected system and selected configuration profile separate.

A configured profile whose concrete adapter has not yet been implemented will fail safely when the bootstrap attempts to load that adapter.

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
│   ├── distro.sh
│   ├── execution.sh
│   ├── logging.sh
│   └── ui.sh
├── distros/
│   └── ubuntu.sh
├── modules/
├── profiles/
├── tests/
└── docs/
```

`modules/`, `profiles/`, `tests/`, and `docs/` are populated as their corresponding implementation work is completed.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Host detection, profile selection, adapter validation, configuration, logging, and execution logic are separated so operations can be validated before system changes are applied. Dry-run mode provides a way to preview execution without applying changes.

Command execution and privilege escalation are centralized so system-changing operations use a consistent execution path. Command arguments are not blindly written to logs because future operations may contain credentials, tokens, sensitive URLs, or other values that should not be persisted.

Distribution-specific operations are isolated behind a validated adapter contract so package-manager behavior does not leak into shared application logic.

Loading an adapter does not automatically refresh package indexes or install software.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.