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
* Controlled workstation module loading and validation
* Module package requirement handling
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

| Distribution | Adapter |
| --- | --- |
| Ubuntu | Implemented |
| Debian | Implemented |
| Kali Linux | Implemented |

## Architecture

The project is intentionally split into layers rather than combining host detection, package installation, prompts, and system changes in one script.

```text
Workstation Profile
        │
        ▼
      Modules
        │
        ▼
  Module Framework
        │
        ▼
Distribution Adapter
        │
        ▼
 Execution Layer
        │
        ▼
System Package Manager
```

The application entry flow coordinates these layers:

```text
User
  │
  ▼
bin/linux-workstation-bootstrap
  │
  ▼
lib/bootstrap.sh
  │
  ├── Configuration
  ├── CLI parsing
  ├── Logging
  ├── Runtime validation
  ├── System detection
  ├── Terminal UI
  ├── Execution framework
  ├── Distribution adapter framework
  ├── Module framework
  └── Profile framework
```

The key separation is:

```text
Profiles decide which capabilities are wanted.
Modules define what those capabilities require.
Distribution adapters implement how the operating system satisfies them.
The execution layer controls how system commands are run.
```

This prevents workstation intent from becoming coupled to one Linux distribution or package manager.

## Component Responsibilities

### Entry Point

`bin/linux-workstation-bootstrap` is the public executable.

It enables safe Bash behavior, resolves the project root, loads the bootstrap orchestrator, and passes command-line arguments to `bootstrap_main`.

### Configuration

`config/defaults.sh` contains built-in application defaults and platform mappings, including:

* application identity and version
* minimum Bash version
* supported distributions
* distro-family mappings
* package-manager mappings
* architecture normalization
* logging defaults

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

Shared application and module code does not call `apt-get` directly.

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
module_packages
```

A module may optionally implement:

```text
module_apply
```

Package requirements are delegated to the selected distribution adapter.

A module therefore describes **what capability is required**, while the distro adapter determines **how that capability is installed on the operating system**.

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

`profile_modules` declares one module ID per line.

Profiles are intentionally declarative. They do not contain package-manager commands, package lists, or system-changing operation hooks.

Before a profile can be accepted, every referenced module is loaded and validated.

Profile execution then runs those modules in declaration order through the shared module framework.

## Execution Flow

The bootstrap foundation establishes the host and distribution layer:

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

The workstation configuration layers build on that foundation:

```text
Select workstation profile
       │
       ▼
Load profile
       │
       ▼
Validate profile contract
       │
       ▼
Validate referenced modules
       │
       ▼
Execute modules in profile order
       │
       ▼
Resolve module requirements
       │
       ▼
Selected distro adapter
       │
       ▼
Shared execution layer
```

Workstation profile selection through the public CLI is introduced separately. Loading the profile framework itself does not install software.

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
        │
        ▼
Developer modules
        │
        ▼
Ubuntu adapter
```

Keeping these concepts separate allows the same workstation profile to eventually operate across multiple supported Linux distributions.

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

A security-focused profile could reuse some of those same modules while selecting additional security capabilities.

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
│   ├── profile.sh
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

Concrete workstation modules and profiles are added independently from their shared frameworks.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Host detection, distribution selection, adapter validation, module validation, profile validation, configuration, logging, and execution logic are separated so operations can be checked before system changes are applied.

Dry-run mode provides a way to preview execution without applying changes.

Command execution and privilege escalation are centralized so system-changing operations use a consistent execution path. Command arguments are not blindly written to logs because future operations may contain credentials, tokens, sensitive URLs, or other values that should not be persisted.

Distribution-specific operations are isolated behind a validated adapter contract.

Modules do not call package managers directly.

Profiles do not contain package-manager commands or duplicate module implementation.

Loading a distro adapter, module, or profile does not itself change the workstation.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.