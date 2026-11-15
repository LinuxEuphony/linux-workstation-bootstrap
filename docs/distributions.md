# Distribution Support

Linux Workstation Bootstrap separates workstation intent from operating-system-specific package management.

Workstation profiles and modules remain portable. Distribution adapters and package capability mappings provide the operating-system-specific implementation.

## Supported Distributions

| Distribution | Family | Package Manager | Architectures |
| --- | --- | --- | --- |
| Ubuntu | Debian | APT | amd64, arm64 |
| Debian | Debian | APT | amd64, arm64 |
| Kali Linux | Debian | APT | amd64, arm64 |
| Fedora Linux | RPM | DNF | amd64, arm64 |

Other Linux distributions may already be detectable without being supported for installation.

Arch Linux is currently detectable but does not yet have an implemented adapter or package capability mapping.

## Distribution Architecture

Distribution support consists of two separate components:

```text
distros/<profile>.sh
config/packages/<profile>.sh
```

The distribution adapter owns package-manager behaviour.

The package mapping owns distribution-specific package names.

Shared modules must not contain package-manager commands or distribution-specific package names.

The flow is:

```text
Module
  |
  v
Portable Capability
  |
  v
Distribution Package Mapping
  |
  v
Distribution Adapter
  |
  v
Shared Execution Layer
```

## Distribution Adapter Contract

Every supported distribution adapter must provide:

```text
distro_validate_environment
distro_update_package_index
distro_install_packages
distro_install_local_package
distro_package_state
```

Adapters are loaded through `lib/distro.sh`.

The shared adapter loader validates this contract before an adapter can be used.

## Package State

Every adapter must distinguish between:

```text
installed
absent
query failure
```

An absent package is a valid state and does not represent a package-manager failure.

A package-state query failure must not be silently treated as package absence.

This distinction is required for safe and idempotent execution planning.

## Debian Family

Ubuntu, Debian, and Kali Linux use:

```text
family          debian
package manager apt
```

Package installation is implemented through `apt-get`.

Installed package state is queried using `dpkg-query`.

Local distribution packages are installed through the same controlled APT adapter rather than invoking package-management commands directly from modules.

## Fedora Linux

Fedora uses:

```text
family          rpm
package manager dnf
```

Package installation and repository metadata refresh are implemented through DNF.

Installed package state is queried through RPM.

Fedora package names are defined only in:

```text
config/packages/fedora.sh
```

Examples of capability translation include:

```text
build-toolchain
    gcc
    gcc-c++
    make

docker-engine
    moby-engine

ffmpeg
    ffmpeg-free

pkg-config
    pkgconf-pkg-config

postgresql-client
    postgresql

xz
    xz
```

These differences remain invisible to workstation modules.

For example, the `development-tools` module requests:

```text
build-toolchain
pkg-config
```

It does not need to know whether those capabilities are implemented through Debian packages or Fedora packages.

## Fedora Container Support

The portable capability:

```text
docker-engine
```

maps to Fedora's:

```text
moby-engine
```

The package provides the Docker-compatible engine and pulls its Docker CLI dependency through Fedora package metadata.

The `containers-virtualization` module continues to declare the required `docker` group through the shared managed-account framework.

The module itself contains no Fedora-specific account or package-management logic.

## Fedora Multimedia Support

Fedora's repository-provided FFmpeg implementation is:

```text
ffmpeg-free
```

It provides the `ffmpeg` command expected by the desktop and media module.

Its codec availability can differ from builds distributed through third-party multimedia repositories.

Linux Workstation Bootstrap does not silently enable third-party repositories to expand codec availability. Such repository configuration belongs in the controlled external installer or managed configuration framework if added in the future.

## Dry-Run Behaviour

Distribution adapters must preserve the shared dry-run contract.

For example, Fedora planning may determine that:

```text
gcc
gcc-c++
make
moby-engine
postgresql
```

are absent and require installation.

During dry-run, the complete execution plan is shown, but DNF is not invoked.

## Privileged Execution

Distribution adapters do not invoke privilege escalation tools directly.

Operations requiring root privileges are routed through:

```text
lib/execution.sh
```

This keeps privilege handling consistent across distributions.

## Adding Another Distribution

A new supported distribution requires:

```text
distribution detection or family mapping
supported distribution registration
supported architecture declaration
distribution adapter
capability package mapping
controlled adapter tests
capability-resolution tests
profile planning tests
documentation
```

A distribution must not be added to `LWBS_SUPPORTED_DISTROS` until both its adapter and capability mapping are implemented and validated.

The next planned distribution family is Arch Linux using Pacman.