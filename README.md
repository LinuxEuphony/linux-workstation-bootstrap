# Linux Workstation Bootstrap

A modular, distro-aware Linux workstation bootstrap utility for configuring Linux workstations consistently and safely.

Linux Workstation Bootstrap replaces a monolithic workstation setup script with reusable modules, portable software capabilities, distribution-specific adapters, execution planning, verification, and automated validation.

## Features

- Linux distribution, version, codename, and architecture detection
- Ubuntu, Debian, and Kali Linux support
- portable capability-to-package resolution
- distro-specific package adapters
- package installation-state detection
- idempotent package installation
- modular workstation capabilities
- declarative workstation profiles
- controlled external software installation
- dry-run execution
- execution planning and confirmation
- post-install verification and execution summaries
- user-local configuration
- persistent execution logging
- automated Bash tests
- ShellCheck and shfmt validation
- GitHub Actions CI

## Supported Distributions

| Distribution | Adapter | Package Mapping | Package State |
| --- | --- | --- | --- |
| Ubuntu | Yes | Yes | Yes |
| Debian | Yes | Yes | Yes |
| Kali Linux | Yes | Yes | Yes |

The architecture is designed to support additional Linux distributions without adding distro-specific logic to shared workstation modules.

## Architecture

The project separates workstation intent from operating-system implementation.

```text
Workstation Profile
        |
        v
      Modules
        |
        v
Portable Capabilities
        |
        v
Distro Package Mapping
        |
        v
Package State Check
        |
   +----+----+
   |         |
  skip    install
             |
             v
    Distribution Adapter
             |
             v
      Execution Layer
```

The core responsibility boundaries are:

```text
Profiles             decide which modules are required
Modules              describe workstation capabilities
Capability mappings  translate capabilities into distro packages
Distro adapters      perform operating-system-specific operations
Execution layer      controls command execution and privileges
Verification         confirms the resulting workstation state
```

Software that cannot be installed through normal distribution repositories uses the separate external installer framework.

## Modules

Modules represent reusable workstation capabilities and live under:

```text
modules/
```

Modules declare portable capabilities rather than package-manager commands or distro-specific package names.

The first workstation module is:

```text
common-utilities
```

It currently provides:

```text
curl
dos2unix
nano
sed
wget
xz
```

For Debian-family distributions, for example, the portable `xz` capability resolves to the `xz-utils` package.

## Profiles

Profiles compose modules into workstation configurations and live under:

```text
profiles/
```

A profile selects modules without duplicating their implementation.

Conceptually:

```text
developer
├── common-utilities
├── development-tools
├── containers
└── database-tools
```

Profiles remain independent of the selected Linux distribution.

## Installation State and Idempotency

Package and external software state is checked before installation.

```text
installed      -> skip
absent         -> install
unknown/error  -> stop safely
```

Repeated runs therefore avoid reinstalling already-satisfied requirements.

Dry-run performs the same read-only state resolution without applying changes.

## Execution Planning

Workstation changes are resolved before they are executed.

```text
Profile
  |
  v
Modules
  |
  v
Capabilities
  |
  v
Current State
  |
  v
Execution Plan
  |
  v
Confirmation
  |
  v
Execution
  |
  v
Verification
```

The plan distinguishes between requirements that are already satisfied and those that require installation.

## External Software

Software requiring mechanisms outside normal distro repositories is handled through controlled installer definitions under:

```text
installers/
```

Supported installer methods include:

- repository configuration
- local distribution packages
- archives
- staged installer scripts

External downloads require HTTPS, and remote scripts are not piped directly into a shell.

## Configuration

Repository defaults live in:

```text
config/defaults.sh
```

Optional user configuration normally lives at:

```text
~/.config/linux-workstation-bootstrap/config.conf
```

Configuration precedence is:

```text
Repository Defaults
        |
        v
User Configuration
        |
        v
CLI Arguments
```

Example:

```ini
distro_profile=ubuntu
```

Supported distro profile values are:

```text
auto
ubuntu
debian
kali
```

User configuration is parsed as data and is never sourced as arbitrary shell code.

## Usage

Clone the repository:

```bash
git clone https://github.com/LinuxEuphony/linux-workstation-bootstrap.git
cd linux-workstation-bootstrap
```

Run the bootstrap:

```bash
./bin/linux-workstation-bootstrap
```

Available options:

```text
--distro <profile>   Use a specific distribution profile
--dry-run            Preview actions without applying changes
-y, --yes            Accept supported confirmations non-interactively
--version            Display the application version
-h, --help           Display help
```

Examples:

```bash
./bin/linux-workstation-bootstrap --dry-run --yes
```

```bash
./bin/linux-workstation-bootstrap \
  --distro ubuntu \
  --dry-run
```

## Logging

Execution logs are stored by default under:

```text
~/.local/state/linux-workstation-bootstrap/logs/
```

`XDG_STATE_HOME` is respected when configured.

Logs capture significant bootstrap, planning, state, execution, and verification events without enabling shell tracing or blindly logging command arguments.

## Project Structure

```text
linux-workstation-bootstrap/
├── bin/             # Public CLI entrypoint
├── config/          # Defaults and distro package mappings
├── distros/         # Distribution-specific adapters
├── docs/            # Detailed project documentation
├── installers/      # External software installers
├── lib/             # Shared bootstrap infrastructure
├── modules/         # Reusable workstation capabilities
├── profiles/        # Workstation profile definitions
├── tests/           # Automated Bash tests
└── README.md
```

Important shared components include:

```text
lib/bootstrap.sh       application lifecycle
lib/capability.sh      capability resolution
lib/config.sh          user configuration
lib/distro.sh          distro adapter framework
lib/execution.sh       controlled command execution
lib/external.sh        external installation framework
lib/module.sh          module framework
lib/plan.sh            execution planning
lib/profile.sh         profile framework
lib/verification.sh    post-install verification
```

## Development Validation

Run the automated test suite:

```bash
bash tests/run.sh
```

For repository-wide shell validation:

```bash
mapfile -d '' -t shell_files < <(
  git ls-files -z \
    --cached \
    --others \
    --exclude-standard \
    -- '*.sh' 'bin/*'
)

for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

shellcheck -x "${shell_files[@]}"

shfmt \
  -d \
  -i 4 \
  -ci \
  "${shell_files[@]}"

bash tests/run.sh

git diff --check
```

GitHub Actions performs the same core syntax, linting, formatting, and test validation on repository changes.

## Safety

Linux Workstation Bootstrap is designed around explicit and reviewable system changes.

Key safeguards include:

- dry-run support
- package and software state checks before installation
- execution plans before modification
- centralized privilege handling
- distro-specific package operations isolated in adapters
- portable capabilities instead of package names in modules
- safe failure on unknown installation state
- staged external scripts instead of `curl | sh`
- post-install verification
- user configuration parsed as data
- automated syntax, lint, formatting, and test validation

## Documentation

Detailed design and implementation documentation belongs under:

```text
docs/
```

The repository already includes:

```text
docs/testing.md
```

Additional architecture and framework documentation is maintained separately from the README as those areas evolve.

## Project

Developed under the [LinuxEuphony](https://github.com/LinuxEuphony) organization.