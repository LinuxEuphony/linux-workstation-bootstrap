#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Release package builder.
#
# Creates the distributable Linux Workstation Bootstrap release archive from
# the current repository source.
#
# This file:
# 1. Loads the project version from the authoritative VERSION file.
# 2. Creates a versioned release archive name.
# 3. Copies only runtime and user-facing project files into the release.
# 4. Includes external installer definitions and trusted key material when
#    those directories exist.
# 5. Excludes development-only content such as tests, CI configuration,
#    repository metadata, logs, local state, and generated artifacts.
# 6. Builds a compressed tar archive from an isolated temporary directory.
# 7. Generates a SHA-256 checksum alongside the release archive.
# 8. Cleans temporary packaging state after successful or failed operations.
#
# Release packaging does not publish artifacts or create Git tags.
# Publication is handled separately by the GitHub release workflow.

set -Eeuo pipefail

PACKAGE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd -- "$PACKAGE_SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../lib/version.sh
source "$PACKAGE_ROOT/lib/version.sh"

release_package() {
    local output_directory="${1:-$PACKAGE_ROOT/dist}"
    local package_name
    local temporary_directory
    local package_root
    local archive_path
    local checksum_path
    local checksum
    local path

    # Only files required to run or understand a released build belong in the
    # distribution archive. Development and repository-management content is
    # intentionally omitted.
    local -a included_paths=(
        "VERSION"
        "README.md"
        "bin"
        "config"
        "distros"
        "docs"
        "lib"
        "modules"
        "profiles"
    )

    if ! load_project_version "$PACKAGE_ROOT/VERSION"; then
        return 1
    fi

    package_name="linux-workstation-bootstrap-$LWBS_VERSION"

    if ! mkdir -p -- "$output_directory"; then
        printf 'Error: unable to create release output directory: %s\n' \
            "$output_directory" >&2

        return 1
    fi

    if output_directory="$(
        cd -- "$output_directory"
        pwd
    )"; then
        :
    else
        printf 'Error: unable to resolve release output directory.\n' >&2
        return 1
    fi

    # Package assembly happens outside the repository so generated release
    # content cannot accidentally become part of the source tree.
    if temporary_directory="$(
        mktemp -d "${TMPDIR:-/tmp}/lwbs-release.XXXXXX"
    )"; then
        :
    else
        printf 'Error: unable to create temporary release directory.\n' >&2
        return 1
    fi

    package_root="$temporary_directory/$package_name"

    if ! mkdir -p -- "$package_root"; then
        printf 'Error: unable to create temporary release package directory.\n' \
            >&2

        rm -rf -- "$temporary_directory"
        return 1
    fi

    for path in "${included_paths[@]}"; do
        if [[ ! -e "$PACKAGE_ROOT/$path" ]]; then
            printf 'Error: required release path is unavailable: %s\n' \
                "$path" >&2

            rm -rf -- "$temporary_directory"
            return 1
        fi

        if ! cp -a \
            "$PACKAGE_ROOT/$path" \
            "$package_root/"; then

            printf 'Error: unable to add release path: %s\n' \
                "$path" >&2

            rm -rf -- "$temporary_directory"
            return 1
        fi
    done

    # These directories are optional because the framework can exist before
    # any concrete external installers or trusted signing keys are present.
    for path in installers keys; do
        if [[ ! -e "$PACKAGE_ROOT/$path" ]]; then
            continue
        fi

        if ! cp -a \
            "$PACKAGE_ROOT/$path" \
            "$package_root/"; then

            printf 'Error: unable to add optional release path: %s\n' \
                "$path" >&2

            rm -rf -- "$temporary_directory"
            return 1
        fi
    done

    archive_path="$output_directory/$package_name.tar.gz"
    checksum_path="$archive_path.sha256"

    if ! tar \
        -czf "$archive_path" \
        -C "$temporary_directory" \
        "$package_name"; then

        printf 'Error: unable to create release archive.\n' >&2

        rm -rf -- "$temporary_directory"
        return 1
    fi

    if checksum="$(sha256sum -- "$archive_path")"; then
        :
    else
        printf 'Error: unable to calculate release archive checksum.\n' >&2

        rm -rf -- "$temporary_directory"
        return 1
    fi

    checksum="${checksum%% *}"

    if ! printf '%s  %s\n' \
        "$checksum" \
        "$(basename -- "$archive_path")" >"$checksum_path"; then

        printf 'Error: unable to write release checksum file.\n' >&2

        rm -rf -- "$temporary_directory"
        return 1
    fi

    if ! rm -rf -- "$temporary_directory"; then
        printf 'Error: unable to clean temporary release directory.\n' >&2
        return 1
    fi

    printf '%s\n' "$archive_path"
    printf '%s\n' "$checksum_path"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    release_package "${1:-}"
fi
