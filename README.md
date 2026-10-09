# Linux Workstation Bootstrap

A reusable, distro-aware Linux workstation bootstrap utility for preparing and configuring Linux workstations in a consistent and controlled way.

Linux Workstation Bootstrap is a modular replacement for a monolithic workstation setup script. It separates host detection, portable software intent, distribution-specific package resolution, command execution, installable capabilities, and workstation profiles so each concern can evolve independently.

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
* Portable package capability resolution
* Independent package mappings per distribution profile
* Controlled workstation module loading and validation
* Module capability requirement handling
* Optional module operation hooks
* Controlled workstation profile loading and validation
* Declarative profile-to-module composition
* Profile module validation before execution
* Profile execution through the shared module framework

Supported distribution profiles:

* Ubuntu
* Debian
* Kali Linux

Current distribution adapter status:

| Distribution | Adapter | Package Mapping |
| --- | --- | --- |
| Ubuntu | Implemented | Implemented |
| Debian | Implemented | Implemented |
| Kali Linux | Implemented | Implemented |

## Architecture

The project separates workstation intent from distro-specific implementation.

```text
Workstation Profile
        |
        v
      Modules
        |
        | capabilities
        v
Capability Resolver
        |
        | distro package mapping
        v
Distribution Adapter
        |
        v
 Execution Layer
        |
        v
System Package Manager
```

The application entry flow coordinates these layers:

```text
User
  |
  v
bin/linux-workstation-bootstrap
  |
  v
lib/bootstrap.sh
  |
  +-- Configuration
  +-- CLI parsing
  +-- Logging
  +-- Runtime validation
  +-- System detection
  +-- Terminal UI
  +-- Execution framework
  +-- Distribution adapter framework
  +-- Capability resolution
  +-- Module framework
  `-- Profile framework
```

The key separation is:

```text
Profiles decide which capabilities are wanted.
Modules declare portable software and operation requirements.
Capability mappings translate software intent into distro package names.
Distribution adapters implement package-manager operations.
The execution layer controls how system commands are run.
```

This prevents workstation modules from becoming coupled to one Linux distribution or package manager.

## Component Responsibilities

### Entry Point

`bin/linux-workstation-bootstrap` is the public executable.

It enables safe Bash behavior, resolves the project root, loads the bootstrap orchestrator, and passes command-line arguments to `bootstrap_main`.

### Configuration

`config/defaults.sh` contains built-in application defaults and platform mappings.

Distribution-specific package mappings live separately under:

```text
config/packages/
├── debian.sh
├── kali.sh
└── ubuntu.sh
```

This separation keeps package names out of shared module implementations.

### Bootstrap Orchestration

`lib/bootstrap.sh` coordinates the application lifecycle.

It determines the order in which shared components operate but does not contain distro-specific package commands or workstation module implementations.

### CLI Handling

`lib/arguments.sh` parses command-line options and records runtime selections such as dry-run mode and distribution-profile overrides.

### Core Utilities

`lib/core.sh` contains reusable distro-independent runtime checks and helpers.

### System Detection

`lib/detect.sh` reads the host environment and determines:

* distribution
* version
* codename
* distro family
* architecture
* expected package manager

Detected host information remains separate from the distribution profile selected for execution.

### Logging

`lib/logging.sh` provides persistent per-session application logging.

### Terminal UI

`lib/ui.sh` owns human-facing output, prompts, menus, help, version information, and execution summaries.

### Execution Framework

`lib/execution.sh` centralizes:

* normal command execution
* privileged command execution
* dry-run behavior
* command result logging
* exit-code propagation

System-changing code should use the shared execution layer rather than executing privileged commands directly.

### Distribution Adapter Framework

`lib/distro.sh` loads and validates the selected distribution implementation.

Concrete adapters live under:

```text
distros/
├── debian.sh
├── kali.sh
└── ubuntu.sh
```

Every adapter implements:

```text
distro_validate_environment
distro_update_package_index
distro_install_packages
```

Package-manager commands remain inside the adapters.

### Capability Resolution

`lib/capability.sh` translates portable capability identifiers into package names for the selected distribution profile.

For example, a module can request:

```text
xz
```

without knowing that the Debian-family package is:

```text
xz-utils
```

The mapping is selected independently for each distro:

```text
Module capability
       |
       v
      xz
       |
       +-- Ubuntu -> xz-utils
       +-- Debian -> xz-utils
       `-- Kali   -> xz-utils
```

Future distributions can provide a different package name without changing the module.

A capability may also map to more than one package where a workstation capability requires a package set.

Missing mappings fail explicitly rather than silently skipping requirements.

### Module Framework

`lib/module.sh` loads, validates, and executes reusable workstation capability modules.

Modules live under:

```text
modules/<module-id>.sh
```

Every module implements:

```text
module_id
module_name
module_description
module_capabilities
```

A module may optionally implement:

```text
module_apply
```

`module_capabilities` emits one portable capability identifier per line.

The framework resolves those capabilities using the selected distro package mapping and delegates the resulting package names to:

```text
distro_install_packages
```

Modules therefore do not need to know whether the selected operating system uses `apt-get`, `dnf`, or another package-management implementation.

### Profile Framework

`lib/profile.sh` loads, validates, and executes workstation profiles.

Profiles live under:

```text
profiles/<profile-id>.sh
```

Every profile implements:

```text
profile_id
profile_name
profile_description
profile_modules
```

Profiles are intentionally declarative. They compose modules without containing package-manager commands, package lists, or duplicated module implementation.

## Execution Flow

The bootstrap establishes the host and distro-specific foundation:

```text
Parse CLI arguments
       |
       v
Initialize logging
       |
       v
Validate runtime
       |
       v
Detect host system
       |
       v
Select distribution profile
       |
       v
Load distribution adapter
       |
       v
Validate adapter environment
       |
       v
Load distro capability mapping
```

Workstation configuration then builds on that foundation:

```text
Select workstation profile
       |
       v
Load profile
       |
       v
Validate referenced modules
       |
       v
Execute module
       |
       v
Resolve module capabilities
       |
       v
Distro-specific package names
       |
       v
Selected distro adapter
       |
       v
Shared execution layer
```

Workstation profile selection through the public CLI is introduced separately. Loading the framework itself does not install software.

## Distribution Profiles vs Workstation Profiles

The project uses two different kinds of profiles.

A **distribution profile** selects operating-system behavior:

```text
ubuntu
debian
kali
```

A **workstation profile** selects workstation capabilities:

```text
default
developer
security
```

For example:

```text
Ubuntu distribution profile
        +
Developer workstation profile
        |
        v
Developer modules
        |
        v
Portable capabilities
        |
        v
Ubuntu package mappings
        |
        v
Ubuntu adapter
```

Keeping these concepts separate allows the same workstation profile and modules to operate across multiple Linux distributions.

## Package Capability Model

Capability identifiers represent software intent rather than package-manager syntax.

Examples:

```text
curl
wget
nano
sed
dos2unix
xz
figlet
```

The identifiers should remain stable even when distro package names differ.

For example, a future Fedora mapping can resolve:

```text
xz -> xz
```

while Debian-family mappings continue to resolve:

```text
xz -> xz-utils
```

Adding Fedora therefore requires a Fedora adapter and Fedora capability mappings, not Fedora-specific conditions throughout shared modules.

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

Profiles compose those modules into coherent workstation configurations without duplicating their implementation.

For example:

```text
developer profile
├── common utilities
├── development tools
├── containers
└── database tooling
```

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

The detected system configuration is displayed before a distribution profile, adapter, and package capability mapping are selected.

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

Selecting a different distribution profile does not alter the detected host information.

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
│   ├── defaults.sh
│   └── packages/
│       ├── debian.sh
│       ├── kali.sh
│       └── ubuntu.sh
├── lib/
│   ├── arguments.sh
│   ├── bootstrap.sh
│   ├── capability.sh
│   ├── core.sh
│   ├── detect.sh
│   ├── distro.sh
│   ├── execution.sh
│   ├── logging.sh
│   ├── module.sh
│   ├── profile.sh
│   └── ui.sh
├── distros/
│   ├── debian.sh
│   ├── kali.sh
│   └── ubuntu.sh
├── modules/
├── profiles/
├── tests/
├── docs/
└── README.md
```

Concrete workstation modules and profiles are added independently from their shared frameworks.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Host detection, distribution selection, capability resolution, adapter validation, module validation, profile validation, configuration, logging, and execution logic are separated so operations can be checked before system changes are applied.

Dry-run mode provides a way to preview execution without applying changes.

Command execution and privilege escalation are centralized so system-changing operations use a consistent execution path.

Distribution-specific package names are isolated in package mapping files.

Package-manager commands remain inside distribution adapters.

Modules request portable capabilities instead of embedding distro package names.

Profiles do not contain package-manager commands or duplicate module implementation.

Loading a distro adapter, capability mapping, module, or profile does not itself change the workstation.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.