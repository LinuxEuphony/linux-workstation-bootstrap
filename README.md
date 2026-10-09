# Linux Workstation Bootstrap

A reusable, distro-aware Linux workstation bootstrap utility for preparing and configuring Linux workstations in a consistent and controlled way.

Linux Workstation Bootstrap is a modular replacement for a monolithic workstation setup script. It separates host detection, portable software intent, distribution-specific package resolution, external software installation, installation-state detection, command execution, installable capabilities, and workstation profiles so each concern can evolve independently.

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
* Distribution-specific package-state detection
* Idempotent package installation filtering
* Controlled external software installer loading and validation
* External software installed-state detection
* Idempotent external software execution
* Repository, local-package, archive, and script installation methods
* Predictable temporary staging for external artifacts
* HTTPS-only external artifact downloads
* Local distribution package installation through distro adapters
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

| Distribution | Adapter | Package Mapping | Package State | Local Packages |
| --- | --- | --- | --- | --- |
| Ubuntu | Implemented | Implemented | Implemented | Implemented |
| Debian | Implemented | Implemented | Implemented | Implemented |
| Kali Linux | Implemented | Implemented | Implemented | Implemented |

## Architecture

The project separates workstation intent from distro-specific implementation.

Standard repository software follows the capability path:

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
 Package State Check
        |
   +----+----+
   |         |
installed   absent
   |         |
   v         v
  skip   Distribution Adapter
                 |
                 v
          Execution Layer
                 |
                 v
        System Package Manager
```

Software that cannot be installed exclusively from the standard distribution repositories follows a separate controlled path:

```text
      Modules
        |
        | external software requirement
        v
External Installer
        |
        v
 External State Check
        |
   +----+----+
   |         |
installed   absent
   |         |
   v         v
  skip    Installation Method
              |
              +-- Repository
              +-- Local Package
              +-- Archive
              `-- Installer Script
                       |
                       v
              Shared Execution Layer
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
  +-- External installation framework
  +-- Module framework
  `-- Profile framework
```

The key separation is:

```text
Profiles decide which workstation capabilities are wanted.
Modules declare portable software and operation requirements.
Capability mappings translate portable intent into distro package names.
Distribution adapters determine package state and perform package operations.
External installers define controlled non-standard installation paths.
State checks determine whether installation work is actually required.
The execution layer controls how system commands are run.
```

This prevents workstation modules from becoming coupled to one Linux distribution, package manager, vendor-specific installation mechanism, or package-state implementation.

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

This separation keeps distro-specific package names out of shared module implementations.

### Bootstrap Orchestration

`lib/bootstrap.sh` coordinates the application lifecycle.

It determines the order in which shared components operate but does not contain distro-specific package commands, external software implementations, or workstation module implementations.

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

Package and external-software state decisions are recorded so skipped and required actions remain visible across repeated bootstrap runs.

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
distro_install_local_package
distro_package_state
```

`distro_package_state` provides distro-specific package-state detection.

The function reports one of:

```text
installed
absent
```

An absent package is a successfully determined state, not an error.

A non-zero return code means that package state could not be determined reliably. The bootstrap treats that as a failure instead of assuming the package is absent.

For the current Debian-family adapters, package state is determined using:

```text
dpkg-query
```

The same abstraction allows future distributions to use their native mechanisms:

```text
Debian family -> dpkg-query
Fedora        -> rpm or DNF state mechanisms
Arch          -> pacman state mechanisms
```

`distro_install_local_package` provides the distro-specific implementation for a previously downloaded local package file.

For example:

```text
Ubuntu / Debian / Kali
        |
        v
apt-get install ./package.deb
```

Future adapters can provide their own equivalent operations without changing the external installation framework.

Package-manager commands remain inside distribution adapters.

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

Future distributions can provide different mappings without changing the module.

For example:

```text
Fedora -> xz
Arch   -> xz
```

A capability may also map to more than one package where a workstation capability requires a package set.

Resolved package names are deduplicated before package-state evaluation.

Missing mappings fail explicitly rather than silently skipping requirements.

### Idempotent Package Installation

Resolved packages are checked before installation.

For each package:

```text
Resolved package
       |
       v
distro_package_state
       |
   +---+---+
   |       |
installed absent
   |       |
   v       v
  skip   install
```

Packages that are already installed are not sent back to the package manager.

For example:

```text
curl      -> installed -> skip
xz-utils  -> absent    -> install
```

If all package requirements for a module are already satisfied, package installation is skipped completely.

Package-state detection remains centralized in distro adapters rather than being duplicated in each module.

This makes repeated bootstrap runs safe and predictable.

### External Installation Framework

`lib/external.sh` provides a controlled path for software that is not installed exclusively from the selected distribution's standard package repositories.

External installer definitions live under:

```text
installers/<installer-id>.sh
```

Every external installer implements:

```text
external_id
external_name
external_description
external_method
external_state
```

`external_state` must report:

```text
installed
```

or:

```text
absent
```

A non-zero return code means the installer could not determine current software state.

Unknown state is treated as an error rather than silently assuming the software is absent.

Supported installation methods are:

```text
repository
package
archive
script
```

Each method requires its matching implementation:

```text
external_repository_apply
external_package_apply
external_archive_apply
external_script_apply
```

An installer may optionally implement:

```text
external_validate_environment
```

Environment validation and installation are only required when `external_state` reports that the software is absent.

If the external software is already installed:

```text
External installer
       |
       v
 external_state
       |
   installed
       |
       v
      skip
```

The framework provides controlled helpers for:

* HTTPS artifact downloads
* temporary installation staging
* local distribution package installation
* installation of prepared system files
* tar archive extraction
* ZIP archive extraction
* staged installer-script execution

External installation logic remains software-specific rather than being added to the bootstrap core.

#### Repository Installations

Repository-based software can prepare vendor repository metadata or signing material and install it through controlled system-file operations.

Repository configuration remains distinct from normal package installation.

#### Local Packages

Downloaded distribution packages are passed back to the selected distro adapter.

This preserves distro independence:

```text
External Installer
        |
        v
Local package
        |
        v
Distribution Adapter
        |
        +-- Debian family -> .deb
        +-- Fedora        -> .rpm
        `-- Arch          -> local package format
```

Fedora and Arch support are future targets and are not currently implemented.

#### Archive Installations

Archive-based software can be downloaded into temporary staging and extracted using controlled helpers.

The framework currently supports tar-compatible archives and ZIP archives.

#### Installer Scripts

Installer scripts must first exist as local staged files.

The framework intentionally does not provide a primitive equivalent to:

```text
curl <url> | sh
```

A script must instead be:

```text
downloaded
    |
    v
staged locally
    |
    v
executed through an explicit interpreter
```

Artifact integrity and installer verification are handled by dedicated integrity work rather than silently trusting downloaded content.

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

The framework:

1. resolves those capabilities using the selected distro package mapping
2. checks each resolved package through `distro_package_state`
3. skips packages already installed
4. sends only missing packages to `distro_install_packages`

Modules therefore do not implement their own package-state detection.

Modules also do not need to know whether the selected operating system uses `apt-get`, `dnf`, `pacman`, or another package-management implementation.

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

Profiles are intentionally declarative. They compose modules without containing package-manager commands, package lists, package-state logic, or duplicated module implementation.

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

Workstation configuration then builds on that foundation.

Repository-backed capability:

```text
Workstation profile
       |
       v
Module
       |
       v
Portable capability
       |
       v
Distro package mapping
       |
       v
Package state check
       |
  +----+----+
  |         |
skip     install
            |
            v
Distribution adapter
            |
            v
Shared execution layer
```

External software:

```text
Workstation module
       |
       v
External installer definition
       |
       v
External state check
       |
  +----+----+
  |         |
skip     install
            |
            v
Explicit installation method
            |
            v
External framework helper
            |
            v
Distribution adapter and/or
shared execution layer
```

Workstation profile selection through the public CLI is introduced separately. Loading the frameworks themselves does not install software.

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
Package-state checks
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

For example:

```text
Ubuntu -> xz-utils
Debian -> xz-utils
Kali   -> xz-utils
Fedora -> xz
Arch   -> xz
```

Fedora and Arch are future support targets. Their package managers, state mechanisms, and mappings should be added through distro adapters and capability mapping files rather than conditions inside shared modules.

## Idempotency

Linux Workstation Bootstrap is designed to be safely rerunnable.

A repeated run should evaluate the current workstation state before attempting installation.

For repository packages:

```text
already installed -> skip
missing           -> install
unknown state     -> fail safely
```

For external software:

```text
already installed -> skip
missing           -> execute installer
unknown state     -> fail safely
```

A state-check failure is never silently interpreted as absence.

This protects against unnecessary reinstallations and prevents uncertain state from triggering unintended system changes.

Dry-run mode still evaluates current installation state so it can distinguish operations that are already satisfied from operations that would be required.

## Standard vs External Software

Software from the selected distribution's normal repositories should use:

```text
Capability
    |
    v
Package Mapping
    |
    v
Package State
    |
    v
Distro Adapter
```

Software requiring additional mechanisms should use:

```text
External Installer
```

Examples of external installation candidates include:

```text
vendor repositories
vendor distribution packages
downloaded archives
language-package-manager tools
explicit installer scripts
```

The external path should not be used merely to bypass normal package capability resolution.

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
* `dpkg-query`

Some external installation methods may additionally require utilities such as:

* `curl`
* `tar`
* `unzip`

Specific external installer definitions are responsible for validating the tools they require.

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

Installation-state decisions, skipped package requirements, missing packages, external-software state checks, installation attempts, and failures are recorded in the session log.

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
│   ├── external.sh
│   ├── logging.sh
│   ├── module.sh
│   ├── profile.sh
│   └── ui.sh
├── distros/
│   ├── debian.sh
│   ├── kali.sh
│   └── ubuntu.sh
├── installers/
├── modules/
├── profiles/
├── tests/
├── docs/
└── README.md
```

The `installers/` directory contains software-specific external installer definitions as they are introduced.

Concrete workstation modules and profiles are added independently of their shared frameworks.

## Safety

Linux Workstation Bootstrap is designed to make system changes deliberately and visibly.

Host detection, distribution selection, capability resolution, package-state detection, external installer validation, external software state detection, adapter validation, module validation, profile validation, configuration, logging, and execution logic are separated so operations can be checked before system changes are applied.

Dry-run mode provides a way to preview execution without applying changes.

Current installation state is evaluated before package or external software installation.

Already-satisfied requirements are skipped.

Unknown or failed state checks stop execution rather than being interpreted as missing software.

Command execution and privilege escalation are centralized so system-changing operations use a consistent execution path.

Distribution-specific package names are isolated in package mapping files.

Distribution-specific package-state checks remain inside distro adapters.

Package-manager commands remain inside distribution adapters.

Modules request portable capabilities instead of embedding distro package names.

Modules do not duplicate package-state detection logic.

External software uses explicit, reviewable installation methods and explicit installed-state checks.

External downloads require HTTPS.

Remote scripts are not piped directly into a shell.

Temporary external installation files are staged predictably and cleaned after execution.

Profiles do not contain package-manager commands or duplicate module implementation.

Loading a distro adapter, capability mapping, external installer definition, module, or profile does not itself change the workstation.

Artifact integrity and external installer verification are separate concerns that build on the external installation framework.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.