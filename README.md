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
* Debian package-management adapter
* Kali Linux package-management adapter
* Package index refresh support through distribution adapters
* Package installation support through distribution adapters
* Controlled workstation module loading
* Module contract validation
* Module package requirement handling
* Optional module operation hooks
* Module execution through the selected distribution adapter

Supported distribution profiles:

* Ubuntu
* Debian
* Kali Linux

Current adapter implementation status:

| Profile | Adapter |
| --- | --- |
| Ubuntu | Implemented |
| Debian | Implemented |
| Kali Linux | Implemented |

## Architecture

The project is intentionally split into layers rather than placing detection, package installation, prompts, and system changes in one script.

```text
                         profiles/
                             │
                             ▼
                          modules/
                             │
                             ▼
User                 lib/module.sh
  │                        │
  ▼                        │
bin/linux-workstation-bootstrap
  │                        │
  └────────────┬───────────┘
               ▼
        lib/bootstrap.sh
               │
      ┌────────┼───────────────┐
      │        │               │
      ▼        ▼               ▼
  Detection  Execution     lib/distro.sh
                              │
                              ▼
                       distros/<profile>.sh
                              │
                              ▼
                         Package manager
```

Shared support around the bootstrap orchestration includes configuration, logging, CLI parsing, runtime validation, and terminal UI.

The main architectural responsibilities are:

* **Entry point**: `bin/linux-workstation-bootstrap` establishes safe Bash behavior, resolves the repository root, and hands control to `bootstrap_main`.
* **Bootstrap orchestration**: `lib/bootstrap.sh` coordinates the application lifecycle without containing distro-specific installation commands.
* **Configuration**: `config/defaults.sh` contains built-in application defaults, supported distro mappings, architecture mappings, and logging defaults.
* **CLI parsing**: `lib/arguments.sh` interprets command-line options and records requested runtime behavior.
* **Core utilities**: `lib/core.sh` provides distro-independent runtime checks and reusable helpers.
* **System detection**: `lib/detect.sh` determines the actual host distribution, distro family, architecture, and expected package manager.
* **Logging**: `lib/logging.sh` creates and writes the per-run session log.
* **Terminal UI**: `lib/ui.sh` owns human-facing output, prompts, menus, help, and version display.
* **Execution boundary**: `lib/execution.sh` centralizes command execution, privilege escalation, dry-run handling, and command result logging.
* **Distro adapter framework**: `lib/distro.sh` loads the selected distro adapter and verifies that it implements the required contract.
* **Distribution adapters**: `distros/` contains operating-system-specific package-management implementations.
* **Module framework**: `lib/module.sh` loads, validates, and executes workstation capability modules.
* **Modules**: `modules/` declares reusable workstation capabilities and their requirements.
* **Profiles**: `profiles/` selects groups of modules to form complete workstation configurations.

The key separation is:

```text
Profiles decide which capabilities are wanted.
Modules define what those capabilities require.
Distribution adapters implement how the operating system satisfies them.
Shared libraries provide the infrastructure used by all of them.
```

## Bootstrap Flow

The bootstrap lifecycle currently establishes:

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

The module framework now provides the next execution layer:

```text
Select module
     │
     ▼
Load module
     │
     ▼
Validate module contract
     │
     ▼
Resolve package requirements
     │
     ▼
Selected distro adapter
     │
     ▼
Shared execution layer
```

Profile selection, module dependency resolution, execution planning, and post-install verification are added by later implementation stages.

Loading a distribution adapter or module framework does not itself update repositories or install packages.

## Distribution Adapter Contract

`lib/distro.sh` provides a common interface between shared bootstrap logic and distribution-specific behavior.

Every distribution adapter must implement:

```text
distro_validate_environment
distro_update_package_index
distro_install_packages
```

Current concrete implementations are:

```text
distros/ubuntu.sh
distros/debian.sh
distros/kali.sh
```

Ubuntu, Debian, and Kali Linux all use APT at the current adapter level, but remain separate implementations so distro-specific behavior can evolve independently.

Shared application and module code does not execute `apt-get` directly.

## Module Contract

A workstation module represents one reusable capability.

Modules are loaded from:

```text
modules/<module-id>.sh
```

Every module must provide:

```text
module_id
module_name
module_description
module_packages
```

A module may additionally provide:

```text
module_apply
```

`module_packages` emits one package requirement per line.

The module framework validates these declarations before execution and passes package requirements to:

```text
distro_install_packages
```

This means a module never needs to know whether the selected distro adapter uses `apt-get` or another package-management implementation.

`module_apply` is reserved for module-specific operations that cannot be represented as package installation. Mutating operations implemented there must use the project's shared execution and configuration facilities so dry-run and safety behavior remain consistent.

Modules must not call package managers directly.

Package capability mapping is introduced separately so shared modules can eventually express portable package intent where distro package names differ.

## Modules and Profiles

Modules represent reusable workstation capabilities such as:

```text
common utilities
development tools
containers
database tooling
desktop and media applications
security tooling
hardware and power management
```

Profiles compose modules into complete workstation configurations such as:

```text
default workstation
developer workstation
security workstation
```

This allows workstation intent to remain independent from the distribution-specific mechanism used to satisfy it.

## Requirements

* Linux
* Bash 5 or newer
* `/etc/os-release`

Ubuntu, Debian, and Kali Linux package operations additionally require:

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

```bash
./bin/linux-workstation-bootstrap --distro debian --dry-run
```

```bash
./bin/linux-workstation-bootstrap --distro kali --dry-run
```

Selecting a different distribution profile does not alter the detected host information. The bootstrap keeps the detected system and selected configuration profile separate.

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
│   ├── module.sh
│   └── ui.sh
├── distros/
│   ├── debian.sh
│   ├── kali.sh
│   └── ubuntu.sh
├── modules/
├── profiles/
├── tests/
└── docs/
```

The framework under `lib/` is implemented independently from concrete workstation modules. Modules and profiles are populated as their corresponding implementation work is completed.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Host detection, profile selection, adapter validation, module validation, configuration, logging, and execution logic are separated so operations can be validated before system changes are applied. Dry-run mode provides a way to preview execution without applying changes.

Command execution and privilege escalation are centralized so system-changing operations use a consistent execution path. Command arguments are not blindly written to logs because future operations may contain credentials, tokens, sensitive URLs, or other values that should not be persisted.

Distribution-specific operations are isolated behind a validated adapter contract so package-manager behavior does not leak into shared application or module logic.

Modules are validated before execution and delegate package installation to the selected distro adapter.

Loading an adapter or module does not automatically change the workstation.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.